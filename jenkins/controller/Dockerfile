# Controller Jenkins da Carparts: reprodutível (imagem + plugins + JCasC).
# Versão LTS fixada; para atualizar, troque a tag, rode "docker compose build"
# num ambiente de cópia e só então em produção.
FROM jenkins/jenkins:2.568.3-lts-jdk21

# sem assistente de configuração: tudo vem do casc.yaml
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"
ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/ref/casc.yaml

COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

COPY --chown=jenkins:jenkins casc.yaml /usr/share/jenkins/ref/casc.yaml

# O controller NÃO recebe Docker CLI nem docker.sock: builds só nos agents.
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=5 \
  CMD curl -fsS http://localhost:8080/login > /dev/null || exit 1
