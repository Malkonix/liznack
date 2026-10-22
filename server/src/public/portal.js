// Portal del administrador: comportamiento mínimo, sin estado propio.
// Todo lo que importa vive en el servidor.

// 1. Confirmación para acciones destructivas (anular venta, borrar cuenta).
document.addEventListener('submit', (evento) => {
  const boton = evento.submitter;
  const mensaje = boton?.dataset?.confirmar;
  if (!mensaje) return;
  if (!window.confirm(mensaje)) {
    evento.preventDefault();
    return;
  }
  boton.disabled = true;
});

// 2. Abrir y cerrar los diálogos de edición.
document.addEventListener('click', (evento) => {
  const abrir = evento.target.closest('[data-abrir]');
  if (abrir) {
    const dialogo = document.getElementById(abrir.dataset.abrir);
    if (dialogo) dialogo.showModal();
    return;
  }
  const cerrar = evento.target.closest('[data-cerrar]');
  if (cerrar) {
    cerrar.closest('dialog')?.close();
  }
});

// 3. Cerrar al hacer clic fuera del contenido del diálogo.
document.addEventListener('click', (evento) => {
  if (evento.target instanceof HTMLDialogElement) evento.target.close();
});
