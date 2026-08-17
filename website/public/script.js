const menuButton = document.querySelector("[data-menu-button]");
const menu = document.querySelector("[data-menu]");
const header = document.querySelector("[data-header]");

menuButton?.addEventListener("click", () => {
  const open = menuButton.getAttribute("aria-expanded") === "true";
  menuButton.setAttribute("aria-expanded", String(!open));
  menu?.classList.toggle("open", !open);
});

menu?.querySelectorAll("a").forEach((link) => {
  link.addEventListener("click", () => {
    menuButton?.setAttribute("aria-expanded", "false");
    menu?.classList.remove("open");
  });
});

window.addEventListener("scroll", () => header?.classList.toggle("scrolled", window.scrollY > 24), { passive: true });

document.querySelectorAll("[data-copy]").forEach((button) => {
  button.addEventListener("click", async () => {
    await navigator.clipboard.writeText(button.dataset.copy);
    const label = button.querySelector("b");
    if (!label) return;
    label.textContent = "Copied";
    setTimeout(() => { label.textContent = "Copy"; }, 1600);
  });
});

document.querySelectorAll("[data-year]").forEach((element) => { element.textContent = new Date().getFullYear(); });

const reveals = document.querySelectorAll(".reveal");
if ("IntersectionObserver" in window && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12 });
  reveals.forEach((element) => observer.observe(element));
} else {
  reveals.forEach((element) => element.classList.add("visible"));
}
