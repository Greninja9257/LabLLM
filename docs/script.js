document.documentElement.classList.add("js");

const glow = document.querySelector(".cursor-glow");

window.addEventListener("pointermove", (event) => {
  if (!glow) return;
  glow.style.left = `${event.clientX}px`;
  glow.style.top = `${event.clientY}px`;
});

const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("visible");
      observer.unobserve(entry.target);
    });
  },
  { threshold: 0.14 }
);

document.querySelectorAll(".reveal").forEach((element) => observer.observe(element));

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const canvas = document.querySelector(".word-field");
const ctx = canvas?.getContext("2d");
const words = [
  "attention",
  "context",
  "token",
  "gradient",
  "learn",
  "predict",
  "checkpoint",
  "validation",
  "sample",
  "loss",
  "dataset",
  "adapter",
  "transformer",
  "chat",
  "MLX",
  "SwiftUI"
];

let particles = [];
let width = 0;
let height = 0;
let pixelRatio = 1;

function resizeWordField() {
  if (!canvas || !ctx) return;
  pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
  width = window.innerWidth;
  height = window.innerHeight;
  canvas.width = Math.floor(width * pixelRatio);
  canvas.height = Math.floor(height * pixelRatio);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  ctx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);

  const targetCount = Math.min(86, Math.max(34, Math.floor((width * height) / 18000)));
  particles = Array.from({ length: targetCount }, (_, index) => ({
    word: words[index % words.length],
    x: Math.random() * width,
    y: Math.random() * height,
    vx: (Math.random() - 0.5) * 0.28,
    vy: (Math.random() - 0.5) * 0.22,
    phase: Math.random() * Math.PI * 2,
    size: 11 + Math.random() * 8,
    alpha: 0.11 + Math.random() * 0.22
  }));
}

function drawWordField(time) {
  if (!canvas || !ctx || reducedMotion) return;
  ctx.clearRect(0, 0, width, height);
  ctx.font = "700 14px Inter, system-ui, sans-serif";
  ctx.textBaseline = "middle";

  for (const particle of particles) {
    particle.x += particle.vx + Math.sin(time * 0.00025 + particle.phase) * 0.08;
    particle.y += particle.vy + Math.cos(time * 0.00021 + particle.phase) * 0.06;

    if (particle.x < -120) particle.x = width + 120;
    if (particle.x > width + 120) particle.x = -120;
    if (particle.y < -40) particle.y = height + 40;
    if (particle.y > height + 40) particle.y = -40;

    const glowAmount = 0.04 + Math.sin(time * 0.001 + particle.phase) * 0.035;
    ctx.globalAlpha = particle.alpha + glowAmount;
    ctx.font = `800 ${particle.size}px Inter, system-ui, sans-serif`;
    ctx.fillStyle = particle.word === "validation" || particle.word === "loss" ? "#ffbd73" : "#eaf6ff";
    ctx.fillText(particle.word, particle.x, particle.y);
  }

  ctx.globalAlpha = 1;
  requestAnimationFrame(drawWordField);
}

if (canvas && ctx && !reducedMotion) {
  resizeWordField();
  window.addEventListener("resize", resizeWordField);
  requestAnimationFrame(drawWordField);
}

const generated = document.querySelector(".generated-text");
const sampleText = "the loss curve had become a map: blue for learning, orange for honesty, and a checkpoint waiting to speak.";
let typed = 0;

function typeSample() {
  if (!generated || reducedMotion) {
    if (generated) generated.textContent = sampleText;
    return;
  }
  generated.textContent = sampleText.slice(0, typed);
  typed = (typed + 1) % (sampleText.length + 32);
  setTimeout(typeSample, typed === 0 ? 600 : 42);
}
typeSample();

const metric = document.querySelector("[data-count]");
if (metric && !reducedMotion) {
  let start;
  const target = Number(metric.dataset.count || "0");
  const animateCount = (time) => {
    start ??= time;
    const progress = Math.min((time - start) / 1400, 1);
    const eased = 1 - Math.pow(1 - progress, 3);
    metric.textContent = Math.floor(target * eased).toLocaleString();
    if (progress < 1) requestAnimationFrame(animateCount);
  };
  requestAnimationFrame(animateCount);
}

const stepReadout = document.querySelector(".step-readout");
if (stepReadout && !reducedMotion) {
  let step = 0;
  setInterval(() => {
    step = (step + 40) % 1280;
    stepReadout.textContent = step.toLocaleString();
  }, 480);
}

const heroStates = [
  {
    title: "training run",
    kicker: "training",
    headline: "watch the curve bend",
    body: "Blue train loss, orange validation loss, live samples, and checkpoints in one workspace.",
    aLabel: "tokens/sec",
    a: "1,860",
    bLabel: "checkpoint",
    b: "step 1,240",
    cLabel: "mode",
    c: "fine-tune"
  },
  {
    title: "sampling playground",
    kicker: "sampling",
    headline: "generate in the prompt",
    body: "Change temperature, continue the text, compare settings, and keep useful generations nearby.",
    aLabel: "temperature",
    a: "0.8",
    bLabel: "top-p",
    b: "0.92",
    cLabel: "tokens",
    c: "256"
  },
  {
    title: "checkpoint manager",
    kicker: "checkpoints",
    headline: "keep the run that worked",
    body: "Load, continue, rename, quantize, and compare checkpoints without losing the experiment.",
    aLabel: "best val",
    a: "2.41",
    bLabel: "saved",
    b: "8 runs",
    cLabel: "status",
    c: "ready"
  }
];

const heroTitle = document.querySelector(".hero-state-title");
const heroKicker = document.querySelector(".hero-state-kicker");
const heroHeadline = document.querySelector(".hero-state-overlay strong");
const heroBody = document.querySelector(".hero-state-overlay p");
const heroMetricALabel = document.querySelector(".hero-metric-a-label");
const heroMetricA = document.querySelector(".hero-metric-a");
const heroMetricBLabel = document.querySelector(".hero-metric-b-label");
const heroMetricB = document.querySelector(".hero-metric-b");
const heroMetricCLabel = document.querySelector(".hero-metric-c-label");
const heroMetricC = document.querySelector(".hero-metric-c");

function applyHeroState(state) {
  if (!heroTitle || !heroKicker || !heroHeadline || !heroBody) return;
  heroTitle.textContent = state.title;
  heroKicker.textContent = state.kicker;
  heroHeadline.textContent = state.headline;
  heroBody.textContent = state.body;
  heroMetricALabel.textContent = state.aLabel;
  heroMetricA.textContent = state.a;
  heroMetricBLabel.textContent = state.bLabel;
  heroMetricB.textContent = state.b;
  heroMetricCLabel.textContent = state.cLabel;
  heroMetricC.textContent = state.c;
}

if (!reducedMotion && heroStates.length > 0) {
  let heroIndex = 0;
  setInterval(() => {
    heroIndex = (heroIndex + 1) % heroStates.length;
    applyHeroState(heroStates[heroIndex]);
  }, 4200);
}

const chatGenerated = document.querySelector(".chat-generated");
const chatText = "It is the fixed exam your model keeps retaking. If train loss improves while validation loss gets worse, the model may be memorizing instead of generalizing.";
let chatTyped = 0;

function typeChat() {
  if (!chatGenerated || reducedMotion) {
    if (chatGenerated) chatGenerated.textContent = chatText;
    return;
  }
  chatGenerated.textContent = chatText.slice(0, chatTyped);
  chatTyped = (chatTyped + 1) % (chatText.length + 42);
  setTimeout(typeChat, chatTyped === 0 ? 900 : 32);
}
typeChat();

const progressBars = document.querySelectorAll(".progress-bar em");
const progressReadout = document.querySelector(".progress-readout");
if (!reducedMotion && progressBars.length > 0) {
  let progress = 0;
  setInterval(() => {
    progress = (progress + 3) % 101;
    progressBars.forEach((bar, index) => {
      const value = Math.min(100, Math.max(12, progress - index * 18));
      bar.style.width = `${value}%`;
    });
    if (progressReadout) progressReadout.textContent = `${progress}%`;
  }, 160);
} else {
  progressBars.forEach((bar) => {
    bar.style.width = "72%";
  });
  if (progressReadout) progressReadout.textContent = "72%";
}

const checkpointNodes = Array.from(document.querySelectorAll(".checkpoint-node"));
if (!reducedMotion && checkpointNodes.length > 0) {
  let activeNode = 2;
  setInterval(() => {
    checkpointNodes.forEach((node, index) => {
      node.classList.toggle("active", index === activeNode);
      node.classList.toggle("done", index < activeNode);
    });
    activeNode = (activeNode + 1) % checkpointNodes.length;
  }, 2200);
}
