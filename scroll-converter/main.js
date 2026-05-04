document.addEventListener("wheel", (e) => {
  if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
    return;
  }
  e.preventDefault();
  product_row.scrollLeft += e.deltaY;
}, { passive: false });
