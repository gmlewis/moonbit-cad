// viewer.js — interactive 3D preview for a build package's START-HERE.html.
//
// Loads high-quality OCCT-tessellated assembly.glb (embedded as base64 for
// offline file:// viewing, or fetched over HTTP), falling back to assembly.gltf.
// When explode.json is present, provides an animated Assembly <-> Exploded
// toggle, scrubbable 0%-100% explode slider, Real/Role color mode, camera
// re-framing, and hover part inspection.
import * as THREE from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { GLTFLoader } from "three/addons/loaders/GLTFLoader.js";

const panel = document.querySelector(".model-panel");
const canvas = panel ? panel.querySelector("canvas") : null;
const fallback = panel ? panel.querySelector(".model-fallback") : null;
const hint = panel ? panel.querySelector(".model-hint") : null;

function showHint(message) {
  if (!hint) return;
  hint.textContent = message;
  hint.hidden = false;
}

function base64ToArrayBuffer(b64) {
  const bin = atob(b64.replace(/\s+/g, ""));
  const len = bin.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = bin.charCodeAt(i);
  }
  return bytes.buffer;
}

function easeInOutCubic(x) {
  return x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
}

function humanizePartName(raw) {
  if (!raw) return "";
  return raw
    .replace(/^bldc_actuator_bldc_actuator_/, "")
    .replace(/^bldc_actuator_/, "")
    .replaceAll("_", " ")
    .replaceAll("/", " · ");
}

async function loadModel(loader) {
  const embeddedGlb = document.getElementById("embedded-assembly-glb");
  if (embeddedGlb && embeddedGlb.textContent.trim()) {
    const buf = base64ToArrayBuffer(embeddedGlb.textContent.trim());
    const gltf = await loader.parseAsync(buf, "");
    return { scene: gltf.scene, isOcctGlb: true };
  }
  try {
    const gltf = await loader.loadAsync("assembly.glb");
    return { scene: gltf.scene, isOcctGlb: true };
  } catch (_) {
    // Fall back to legacy glTF JSON.
  }
  const embeddedGltf = document.getElementById("embedded-assembly-gltf");
  if (embeddedGltf && embeddedGltf.textContent.trim()) {
    const gltf = await loader.parseAsync(embeddedGltf.textContent, "");
    return { scene: gltf.scene, isOcctGlb: false };
  }
  const gltf = await loader.loadAsync("assembly.gltf");
  return { scene: gltf.scene, isOcctGlb: false };
}

async function loadExplodeData() {
  const embedded = document.getElementById("embedded-explode-json");
  if (embedded && embedded.textContent.trim()) {
    try {
      return JSON.parse(embedded.textContent);
    } catch (_) {
      return null;
    }
  }
  try {
    const res = await fetch("explode.json");
    if (res.ok) return await res.json();
  } catch (_) {
    // Ignore when explode.json is not present.
  }
  return null;
}

function createToolbar(panelEl, hasExplode) {
  const bar = document.createElement("div");
  bar.className = "viewer-toolbar";
  bar.innerHTML = hasExplode
    ? `
      <button type="button" class="viewer-btn viewer-btn-primary" data-action="toggle-explode" title="Animate between Assembled and Exploded views">
        <span class="viewer-btn-icon">⇕</span>
        <span class="viewer-btn-label">Explode</span>
      </button>
      <label class="viewer-slider-wrap" title="Scrub assembly explosion (0% – 100%)">
        <input type="range" class="viewer-slider" min="0" max="100" value="0" step="0.5" aria-label="Explode amount" />
        <span class="viewer-slider-pct">0%</span>
      </label>
      <button type="button" class="viewer-btn" data-action="toggle-colors" title="Toggle color-coded exploded palette">
        Role Colors
      </button>
      <button type="button" class="viewer-btn" data-action="reset-view" title="Re-center camera on current view">
        Reset View
      </button>
    `
    : `
      <button type="button" class="viewer-btn" data-action="reset-view" title="Re-center camera">
        Reset View
      </button>
    `;
  panelEl.appendChild(bar);

  const tooltip = document.createElement("div");
  tooltip.className = "viewer-part-tooltip";
  tooltip.hidden = true;
  panelEl.appendChild(tooltip);

  return { bar, tooltip };
}

async function init() {
  if (!panel || !canvas) return;

  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
  } catch (error) {
    showHint("WebGL is unavailable; showing the isometric render.");
    return;
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.15;

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(35, 1, 0.001, 100);

  // Crisp 3-point + rim studio lighting so dark CF-nylon housings read clearly.
  scene.add(new THREE.HemisphereLight(0xf6f9ff, 0x334155, 1.55));
  const key = new THREE.DirectionalLight(0xfffaf0, 2.2);
  key.position.set(1.4, 2.4, 1.8);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xdbeafe, 1.05);
  fill.position.set(-1.8, 0.9, 1.2);
  scene.add(fill);
  const rim = new THREE.DirectionalLight(0xe0f2fe, 1.25);
  rim.position.set(-0.6, 1.4, -2.0);
  scene.add(rim);

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;

  const loader = new GLTFLoader();
  let loaded;
  try {
    loaded = await loadModel(loader);
  } catch (error) {
    showHint("3D model unavailable (serve this folder over http); showing the isometric render.");
    return;
  }

  const explodeData = await loadExplodeData();
  const model = loaded.scene;
  if (!loaded.isOcctGlb) {
    // Legacy MoonBit glTF is Z-up; three.js and OCCT GLB are Y-up.
    model.rotation.x = -Math.PI / 2;
  }

  const root = new THREE.Group();
  root.add(model);
  scene.add(root);

  // Enhance materials and bind each part node to its explode vector & window.
  const partMap = (explodeData && explodeData.parts) || {};
  const occCounter = new Map();
  const animatedParts = [];
  const pickableMeshes = [];

  model.traverse((obj) => {
    if (!obj.isMesh) return;
    // Clone material per mesh so hover highlight & role-color cross-fade are isolated.
    if (Array.isArray(obj.material)) {
      obj.material = obj.material.map((m) => m.clone());
    } else if (obj.material) {
      obj.material = obj.material.clone();
    }
    const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
    const baseColors = [];
    for (const m of mats) {
      if (!m || !m.color) continue;
      // Lift pitch-black plastic/CF-nylon slightly so contours and keyways stand out.
      const hsl = { h: 0, s: 0, l: 0 };
      m.color.getHSL(hsl);
      if (hsl.l < 0.08) {
        m.color.setHSL(hsl.h, Math.min(hsl.s, 0.15), 0.14);
      }
      if ("roughness" in m && m.roughness > 0.7) {
        m.roughness = 0.52;
      }
      if ("metalness" in m && m.metalness === 0) {
        m.metalness = 0.12;
      }
      baseColors.push(m.color.clone());
    }

    const name = obj.name || (obj.parent && obj.parent.name) || "";
    obj.userData.displayName = humanizePartName(name);
    obj.userData.baseColors = baseColors;
    pickableMeshes.push(obj);

    const list = partMap[name];
    if (list && list.length > 0) {
      const occ = occCounter.get(name) || 0;
      occCounter.set(name, occ + 1);
      const spec = list[Math.min(occ, list.length - 1)];
      const offset = new THREE.Vector3(spec.offset[0], spec.offset[1], spec.offset[2]);
      const roleColor = spec.color
        ? new THREE.Color(spec.color[0], spec.color[1], spec.color[2])
        : null;
      animatedParts.push({
        obj,
        basePos: obj.position.clone(),
        offset,
        window: spec.window || [0, 1],
        baseColors,
        roleColor,
      });
    }
  });

  const hasExplode = animatedParts.some((p) => p.offset.lengthSq() > 1e-8);

  function computeFitPose() {
    root.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(root);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    const radius = Math.max(size.x, size.y, size.z) * 0.52 || 0.1;
    const distance = radius / Math.sin(THREE.MathUtils.degToRad(35) / 2);
    return { center, distance };
  }

  // Center the assembled model at the world origin.
  root.updateMatrixWorld(true);
  const initBox = new THREE.Box3().setFromObject(root);
  const initCenter = initBox.getCenter(new THREE.Vector3());
  root.position.sub(initCenter);

  let currentT = 0;
  let targetT = 0;
  let isAnimating = false;
  let animStartTime = 0;
  let animFromT = 0;
  let animToT = 0;
  const ANIM_DURATION_MS = 1650;
  let useRoleColors = false;

  // Smooth camera transition targets when clicking Explode / Assemble / Reset.
  let camAnim = null;

  function applyExplode(t) {
    currentT = Math.max(0, Math.min(1, t));
    for (const part of animatedParts) {
      const [w0, w1] = part.window;
      const local = w1 > w0 ? Math.max(0, Math.min(1, (currentT - w0) / (w1 - w0))) : currentT;
      const eased = easeInOutCubic(local);
      part.obj.position.copy(part.basePos).addScaledVector(part.offset, eased);

      if (part.roleColor) {
        const mats = Array.isArray(part.obj.material) ? part.obj.material : [part.obj.material];
        const colorMix = useRoleColors ? 1.0 : eased * 0.85;
        for (let i = 0; i < mats.length; i++) {
          const m = mats[i];
          if (m && m.color && part.baseColors[i]) {
            m.color.copy(part.baseColors[i]).lerp(part.roleColor, colorMix);
          }
        }
      }
    }
  }

  // Precompute assembled & exploded camera poses (preserving current viewing direction).
  applyExplode(0);
  const assembledFit = computeFitPose();
  let explodedFit = assembledFit;
  if (hasExplode) {
    applyExplode(1);
    explodedFit = computeFitPose();
    applyExplode(0);
  }

  function frameCameraInstant(fit) {
    const dir = new THREE.Vector3(0.78, 0.48, 0.82).normalize();
    camera.position.copy(fit.center).addScaledVector(dir, fit.distance * 1.05);
    camera.near = Math.max(fit.distance / 250, 0.0005);
    camera.far = fit.distance * 25;
    camera.updateProjectionMatrix();
    controls.target.copy(fit.center);
    controls.update();
  }

  function startCameraTransition(fit, durationMs = 1100) {
    const curDir = camera.position.clone().sub(controls.target);
    if (curDir.lengthSq() < 1e-8) {
      curDir.set(0.78, 0.48, 0.82);
    }
    curDir.normalize();
    const goalPos = fit.center.clone().addScaledVector(curDir, fit.distance * 1.08);
    camAnim = {
      startTime: performance.now(),
      duration: durationMs,
      fromPos: camera.position.clone(),
      toPos: goalPos,
      fromTarget: controls.target.clone(),
      toTarget: fit.center.clone(),
      near: Math.max(fit.distance / 250, 0.0005),
      far: fit.distance * 25,
    };
  }

  frameCameraInstant(assembledFit);

  // Stop automatic camera transition if user manually grabs the orbit controls.
  controls.addEventListener("start", () => {
    camAnim = null;
  });

  // Build interactive toolbar & tooltip.
  const { bar, tooltip } = createToolbar(panel, hasExplode);
  const toggleBtn = bar.querySelector('[data-action="toggle-explode"]');
  const toggleLabel = toggleBtn ? toggleBtn.querySelector(".viewer-btn-label") : null;
  const slider = bar.querySelector(".viewer-slider");
  const sliderPct = bar.querySelector(".viewer-slider-pct");
  const colorBtn = bar.querySelector('[data-action="toggle-colors"]');
  const resetBtn = bar.querySelector('[data-action="reset-view"]');

  function syncUI() {
    if (slider) slider.value = String(Math.round(currentT * 1000) / 10);
    if (sliderPct) sliderPct.textContent = `${Math.round(currentT * 100)}%`;
    if (toggleLabel) {
      const nextIsAssemble = isAnimating ? animToT > 0.5 : currentT > 0.5;
      toggleLabel.textContent = nextIsAssemble ? "Assemble" : "Explode";
    }
    if (colorBtn) {
      colorBtn.classList.toggle("is-active", useRoleColors);
    }
  }

  if (toggleBtn) {
    toggleBtn.addEventListener("click", () => {
      const goingToExplode = isAnimating ? animToT < 0.5 : currentT < 0.5;
      targetT = goingToExplode ? 1 : 0;
      animFromT = currentT;
      animToT = targetT;
      animStartTime = performance.now();
      isAnimating = true;
      startCameraTransition(goingToExplode ? explodedFit : assembledFit, ANIM_DURATION_MS);
      syncUI();
    });
  }

  if (slider) {
    slider.addEventListener("input", () => {
      isAnimating = false;
      camAnim = null;
      const val = parseFloat(slider.value) / 100;
      applyExplode(val);
      syncUI();
    });
  }

  if (colorBtn) {
    colorBtn.addEventListener("click", () => {
      useRoleColors = !useRoleColors;
      applyExplode(currentT);
      syncUI();
    });
  }

  if (resetBtn) {
    resetBtn.addEventListener("click", () => {
      const fit = computeFitPose();
      startCameraTransition(fit, 650);
    });
  }

  // Hover part inspection via raycaster.
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  let hoveredMesh = null;

  function setHoverEmissive(mesh, active) {
    if (!mesh) return;
    const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    for (const m of mats) {
      if (m && m.emissive) {
        m.emissive.setHex(active ? 0x1d4ed8 : 0x000000);
        m.emissiveIntensity = active ? 0.35 : 0;
      }
    }
  }

  canvas.addEventListener("pointermove", (ev) => {
    if (ev.buttons !== 0) {
      tooltip.hidden = true;
      return;
    }
    const rect = canvas.getBoundingClientRect();
    pointer.x = ((ev.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((ev.clientY - rect.top) / rect.height) * 2 + 1;
    raycaster.setFromCamera(pointer, camera);
    const hits = raycaster.intersectObjects(pickableMeshes, false);
    const hit = hits.length > 0 ? hits[0].object : null;
    if (hit !== hoveredMesh) {
      setHoverEmissive(hoveredMesh, false);
      hoveredMesh = hit;
      setHoverEmissive(hoveredMesh, true);
    }
    if (hoveredMesh && hoveredMesh.userData.displayName) {
      tooltip.textContent = hoveredMesh.userData.displayName;
      tooltip.hidden = false;
    } else {
      tooltip.hidden = true;
    }
  });

  canvas.addEventListener("pointerleave", () => {
    setHoverEmissive(hoveredMesh, false);
    hoveredMesh = null;
    tooltip.hidden = true;
  });

  if (fallback) fallback.hidden = true;
  canvas.hidden = false;
  showHint(hasExplode ? "Drag to orbit · scroll to zoom · hover parts" : "Drag to orbit · scroll to zoom");
  syncUI();

  function resize() {
    const width = panel.clientWidth || 640;
    const height = panel.clientHeight || 520;
    renderer.setSize(width, height, false);
    camera.aspect = width / Math.max(height, 1);
    camera.updateProjectionMatrix();
  }
  window.addEventListener("resize", resize);
  resize();

  renderer.setAnimationLoop((now) => {
    if (isAnimating) {
      const raw = Math.min(1, (now - animStartTime) / ANIM_DURATION_MS);
      const t = animFromT + (animToT - animFromT) * easeInOutCubic(raw);
      applyExplode(t);
      if (raw >= 1) {
        isAnimating = false;
      }
      syncUI();
    }
    if (camAnim) {
      const raw = Math.min(1, (now - camAnim.startTime) / camAnim.duration);
      const e = easeInOutCubic(raw);
      camera.position.lerpVectors(camAnim.fromPos, camAnim.toPos, e);
      controls.target.lerpVectors(camAnim.fromTarget, camAnim.toTarget, e);
      camera.near = camAnim.near;
      camera.far = camAnim.far;
      camera.updateProjectionMatrix();
      if (raw >= 1) camAnim = null;
    }
    controls.update();
    renderer.render(scene, camera);
  });
}

init();
