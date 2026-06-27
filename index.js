const express = require('express');
const app = express();

function salud() {
  return { status: 'ok' };
}

app.get('/health', (req, res) => {
  res.json(salud());
});

app.get('/', (req, res) => {
  res.json({ message: 'demo-api funcionando' });
});

if (require.main === module) {
  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => {
    console.log(`Servidor corriendo en puerto ${PORT}`);
  });
}

module.exports = { app, salud };
