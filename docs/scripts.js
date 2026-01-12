const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.2 }
);

document.querySelectorAll(".section, .card, .code-block, .terminal-card").forEach((el) => {
  el.classList.add("fade-in");
  observer.observe(el);
});

const typewriter = document.querySelector(".typewriter");
if (typewriter) {
  const rawLines = typewriter.dataset.lines || "";
  const lines = rawLines.split("||");
  const typingDelay = 45;
  const lineDelay = 650;
  const loopDelay = 5000;
  let lineIndex = 0;
  let charIndex = 0;

  const cursor = document.createElement("span");
  cursor.className = "typewriter__cursor";

  const renderFrame = () => {
    typewriter.innerHTML = "";
    lines.forEach((line, index) => {
      if (index > lineIndex) return;
      const lineEl = document.createElement("div");
      const isPrompt = line.trim().startsWith("$");
      lineEl.className = `typewriter__line ${
        isPrompt ? "typewriter__line--prompt" : "typewriter__line--output"
      }`;
      const text = index === lineIndex ? line.slice(0, charIndex) : line;
      lineEl.textContent = text;
      if (index === lineIndex) {
        lineEl.appendChild(cursor);
      }
      typewriter.appendChild(lineEl);
    });
  };

  const isInstantLine = (line) =>
    line.startsWith("Generated:") || line.startsWith("Let the glow begin");

  const typeNext = () => {
    if (lineIndex >= lines.length) {
      setTimeout(() => {
        lineIndex = 0;
        charIndex = 0;
        typewriter.innerHTML = "";
        typeNext();
      }, loopDelay);
      return;
    }

    if (isInstantLine(lines[lineIndex])) {
      charIndex = lines[lineIndex].length;
      renderFrame();
      charIndex = 0;
      lineIndex += 1;
      setTimeout(typeNext, lineDelay);
      return;
    }

    if (charIndex <= lines[lineIndex].length) {
      renderFrame();
      charIndex += 1;
      setTimeout(typeNext, typingDelay);
      return;
    }

    charIndex = 0;
    lineIndex += 1;
    setTimeout(typeNext, lineDelay);
  };

  typeNext();
}
