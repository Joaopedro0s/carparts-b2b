// Jenkinsfile · carparts-api · portal de pedidos B2B da Carparts
//
// Fluxo (Multibranch Pipeline):
//   qualquer branch / PR -> Qualidade (lint + testes + auditoria, em paralelo) -> Build da imagem
//   branch main          -> + Publicação no ACR -> Deploy homologação + smoke test
//                           -> Aprovação registrada (input) -> Deploy produção (MESMA imagem, por digest)
//
// Regras de segurança:
//   * nenhum stage roda no controller (agent none no topo; o nó interno tem 0 executores);
//   * segredos só via withCredentials e SEMPRE em aspas simples (quem expande é o shell, não o Groovy);
//   * a imagem é construída uma única vez e promovida por digest (sem recompilar em produção).

// Faz login na Azure com o service principal, executa o bloco e sempre faz logout.
// AZURE_CONFIG_DIR fica no workspace: a sessão não vaza para outros builds do mesmo agent.
def comAzure(Closure corpo) {
    withEnv(["AZURE_CONFIG_DIR=${env.WORKSPACE}/.azure"]) {
        withCredentials([
            usernamePassword(credentialsId: 'azure-sp',
                             usernameVariable: 'AZURE_CLIENT_ID',
                             passwordVariable: 'AZURE_CLIENT_SECRET'),
            string(credentialsId: 'azure-tenant-id', variable: 'AZURE_TENANT_ID'),
            string(credentialsId: 'azure-subscription-id', variable: 'AZURE_SUBSCRIPTION_ID')
        ]) {
            try {
                sh 'scripts/azure-login.sh'
                corpo()
            } finally {
                sh 'az logout --output none || true'
            }
        }
    }
}

pipeline {
    agent none                                   // cada stage escolhe seu agent; nada no controller

    options {
        // teto de segurança do pipeline inteiro (inclui até 1 dia de espera pela aprovação);
        // cada stage com agent tem o seu próprio timeout curto
        timeout(time: 25, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '30', artifactNumToKeepStr: '30'))
        timestamps()
    }

    environment {
        APP       = 'carparts-api'
        ACR_NAME  = 'acrcarparts26179863'               // nome do Azure Container Registry (sem .azurecr.io)
        REGISTRY  = "${ACR_NAME}.azurecr.io"
        CI        = 'true'
    }

    stages {

        stage('Qualidade') {
            options { timeout(time: 15, unit: 'MINUTES') }
            parallel {
                stage('Lint') {
                    agent { docker { image 'node:22-alpine'; label 'linux && docker' } }
                    environment { npm_config_cache = "${env.WORKSPACE}/.npm" }
                    steps {
                        sh 'npm ci --no-audit --no-fund'
                        sh 'npm run lint'
                    }
                    post { always { cleanWs() } }
                }
                stage('Testes') {
                    agent { docker { image 'node:22-alpine'; label 'linux && docker' } }
                    environment { npm_config_cache = "${env.WORKSPACE}/.npm" }
                    steps {
                        sh 'npm ci --no-audit --no-fund'
                        sh 'npm test'                // gera reports/junit.xml
                    }
                    post {
                        always {
                            junit allowEmptyResults: false, testResults: 'reports/junit.xml'
                            cleanWs()
                        }
                    }
                }
                stage('Auditoria de dependências') {
                    agent { docker { image 'node:22-alpine'; label 'linux && docker' } }
                    environment { npm_config_cache = "${env.WORKSPACE}/.npm" }
                    steps {
                        // falha o stage se houver vulnerabilidade alta/crítica nas dependências de produção
                        sh 'npm audit --omit=dev --audit-level=high'
                    }
                    post { always { cleanWs() } }
                }
            }
        }

        stage('Imagem e publicação') {
            agent { label 'linux && docker && azure-cli' }
            options { timeout(time: 20, unit: 'MINUTES') }
            stages {
                stage('Build da imagem') {
                    steps {
                        script {
                            env.GIT_SHORT = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                            env.IMAGE_TAG = "${env.BUILD_NUMBER}-${env.GIT_SHORT}"
                            env.IMAGE     = "${env.REGISTRY}/${env.APP}:${env.IMAGE_TAG}"
                        }
                        sh '''
                            docker build \
                              --build-arg APP_VERSION="$IMAGE_TAG" \
                              --build-arg GIT_COMMIT="$GIT_COMMIT" \
                              -t "$IMAGE" .
                        '''
                    }
                }
                stage('Publicação no ACR') {
                    when { branch 'main' }
                    steps {
                        script {
                            comAzure {
                                sh 'az acr login --name "$ACR_NAME"'
                                sh 'docker push "$IMAGE"'
                                // digest imutável: é ele que será promovido para produção
                                env.IMAGE_DIGEST = sh(
                                    script: 'az acr repository show --name "$ACR_NAME" --image "$APP:$IMAGE_TAG" --query digest --output tsv',
                                    returnStdout: true).trim()
                            }
                        }
                        echo "Imagem publicada: ${env.REGISTRY}/${env.APP}@${env.IMAGE_DIGEST}"
                    }
                }
            }
            post {
                always {
                    sh 'docker image rm "$IMAGE" || true'    // não acumula imagens no agent
                    cleanWs()
                }
            }
        }

        stage('Deploy homologação') {
            when { branch 'main' }
            agent { label 'linux && azure-cli' }
            options {
                timeout(time: 15, unit: 'MINUTES')
                lock(resource: 'carparts-hml')   // um deploy de homologação por vez
            }
            steps {
                milestone(ordinal: 1, label: 'homologacao')   // build mais novo cancela os mais antigos
                script {
                    comAzure {
                        sh 'scripts/deploy.sh hml "$IMAGE_DIGEST" "$IMAGE_TAG"'
                    }
                }
                sh 'scripts/smoke-test.sh "$(cat .deploy-url-hml)" "$GIT_COMMIT"'
            }
            post { always { cleanWs() } }
        }

        stage('Aprovação') {
            when {
                beforeInput true                  // avalia a branch ANTES de pedir aprovação
                branch 'main'
            }
            options { timeout(time: 1, unit: 'DAYS') }
            input {
                message "Publicar carparts-api (build ${env.BUILD_NUMBER}) em PRODUÇÃO? Homologação e smoke test passaram."
                ok 'Aprovar publicação'
                submitter 'aprovador1,aprovador2'  // somente os aprovadores definidos no casc.yaml
                submitterParameter 'APROVADOR'
            }
            // sem agent: a espera não ocupa nenhum executor
            steps {
                milestone(ordinal: 2, label: 'aprovado')      // aprovação de um build novo descarta a espera dos antigos
                script {
                    env.APROVADO_POR   = env.APROVADOR
                    env.APROVADO_EM_MS = "${System.currentTimeMillis()}"   // convertido para data no registro-deploy.sh
                    currentBuild.description = "Aprovado por ${env.APROVADO_POR} · ${env.IMAGE_TAG}"
                }
                echo "Aprovação registrada: ${env.APROVADO_POR} (build ${env.BUILD_NUMBER}, imagem ${env.IMAGE_TAG})"
            }
        }

        stage('Deploy produção') {
            when { branch 'main' }
            agent { label 'linux && azure-cli' }
            options {
                timeout(time: 15, unit: 'MINUTES')
                lock(resource: 'carparts-prd')
            }
            steps {
                milestone(ordinal: 3, label: 'producao')
                script {
                    comAzure {
                        // mesmo digest aprovado em homologação: nada é recompilado
                        sh 'scripts/deploy.sh prd "$IMAGE_DIGEST" "$IMAGE_TAG"'
                    }
                }
                sh 'scripts/smoke-test.sh "$(cat .deploy-url-prd)" "$GIT_COMMIT"'
                sh 'scripts/registro-deploy.sh > deploy-record.json'
                archiveArtifacts artifacts: 'deploy-record.json', fingerprint: true
            }
            post { always { cleanWs() } }
        }
    }

    post {
        success {
            echo "Pipeline concluído: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
        }
        unstable {
            echo 'Build instável: verifique os testes publicados pelo junit.'
        }
        failure {
            script {
                try {
                    mail to: 'devops@carparts.example',
                         subject: "FALHOU: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                         body: "Detalhes em ${env.BUILD_URL}"
                } catch (err) {
                    echo "Aviso: e-mail de falha não enviado (${err.message})."
                }
            }
        }
        fixed {
            echo "Build voltou ao verde: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
        }
    }
}
