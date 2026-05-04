document.addEventListener("wheel", (e) => {
  if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
    return;
  }
  e.preventDefault();
  document.scrollLeft += e.deltaY;
}, { passive: false });
