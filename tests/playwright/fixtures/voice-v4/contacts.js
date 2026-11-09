export default {
  accountIdFromRoute: 9001,
  show: id =>
    Promise.resolve({
      data: {
        payload: {
          id: Number(id),
          name:
            Number(id) === 9100 ? 'Cliente sintético A' : 'Cliente sintético B',
          phone_number: 'Contato de laboratório',
          email: 'laboratorio@example.invalid',
        },
      },
    }),
};
