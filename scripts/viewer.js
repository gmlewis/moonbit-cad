// viewer.js — interactive 3D preview for a build package's START-HERE.html.
//
// Requires three.js from a CDN (pinned in the page's import map). The static
// <img class="model-fallback"> stays visible until the glTF model has loaded,
// so the page degrades cleanly offline and when opened with file:// (browsers
// refuse the model fetch there).
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

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(35, 1, 0.01, 100);
  scene.add(new THREE.HemisphereLight(0xffffff, 0x445566, 2.1));
  const key = new THREE.DirectionalLight(0xffffff, 2.3);
  key.position.set(1.2, 2.2, 1.6);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xffffff, 0.8);
  fill.position.set(-1.6, 0.7, -1.1);
  scene.add(fill);

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;

  let model;
  try {
    const gltf = await new GLTFLoader().loadAsync("assembly.gltf");
    model = gltf.scene;
  } catch (error) {
    showHint("3D model unavailable (serve this folder over http); showing the isometric render.");
    return;
  }

  // The CAD kernel writes Z-up glTF; three.js is Y-up.
  model.rotation.x = -Math.PI / 2;
  const root = new THREE.Group();
  root.add(model);
  scene.add(root);

  root.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(root);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  root.position.sub(center);

  const radius = Math.max(size.x, size.y, size.z) * 0.5 || 0.1;
  const distance = radius / Math.sin(THREE.MathUtils.degToRad(35) / 2);
  camera.position.set(distance * 0.82, distance * 0.58, distance * 0.82);
  camera.near = distance / 200;
  camera.far = distance * 20;
  camera.updateProjectionMatrix();
  controls.target.set(0, 0, 0);
  controls.update();

  if (fallback) fallback.hidden = true;
  canvas.hidden = false;
  showHint("Drag to orbit · scroll to zoom");

  function resize() {
    const width = panel.clientWidth || 640;
    const height = panel.clientHeight || 420;
    renderer.setSize(width, height, false);
    camera.aspect = width / Math.max(height, 1);
    camera.updateProjectionMatrix();
  }
  window.addEventListener("resize", resize);
  resize();

  renderer.setAnimationLoop(() => {
    controls.update();
    renderer.render(scene, camera);
  });
}

init();
