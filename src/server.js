'use strict';

const { criarServidor } = require('./app');

const PORT = Number(process.env.PORT) || 3000;

const servidor = criarServidor();
servidor.listen(PORT, () => {
  console.log(`carparts-api ouvindo na porta ${PORT}`);
});

// Encerramento limpo quando o orquestrador (Container Apps) para a réplica.
process.on('SIGTERM', () => servidor.close(() => process.exit(0)));
