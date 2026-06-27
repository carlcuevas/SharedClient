const { salud } = require('../index');

test('health retorna status ok', () => {
  expect(salud()).toEqual({ status: 'ok' });
});
