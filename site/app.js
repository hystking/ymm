/**
 * ymm — serverless music player
 *
 * Reads playlist.json (a static file you upload to S3) and plays the mp3
 * files it references. No backend required: everything runs in the browser
 * and is served as static assets through CloudFront.
 *
 * playlist.json schema:
 * {
 *   "tracks": [
 *     { "title": "Song", "artist": "Someone", "src": "music/song.mp3" }
 *   ]
 * }
 */
(() => {
  "use strict";

  const audio = document.getElementById("audio");
  const els = {
    art: document.getElementById("art"),
    trackTitle: document.getElementById("trackTitle"),
    trackArtist: document.getElementById("trackArtist"),
    seek: document.getElementById("seek"),
    curTime: document.getElementById("curTime"),
    durTime: document.getElementById("durTime"),
    playBtn: document.getElementById("playBtn"),
    prevBtn: document.getElementById("prevBtn"),
    nextBtn: document.getElementById("nextBtn"),
    shuffleBtn: document.getElementById("shuffleBtn"),
    repeatBtn: document.getElementById("repeatBtn"),
    volume: document.getElementById("volume"),
    playlist: document.getElementById("playlist"),
    status: document.getElementById("status"),
  };

  /** @type {Array<{title:string, artist:string, src:string}>} */
  let tracks = [];
  let current = -1;
  let shuffle = false;
  let repeat = false;
  let seeking = false;

  const fmt = (s) => {
    if (!isFinite(s) || s < 0) return "0:00";
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return `${m}:${String(sec).padStart(2, "0")}`;
  };

  const setStatus = (msg, isError = false) => {
    els.status.textContent = msg || "";
    els.status.classList.toggle("status--error", isError);
  };

  function renderPlaylist() {
    els.playlist.innerHTML = "";
    tracks.forEach((t, i) => {
      const li = document.createElement("li");
      li.className = "playlist__item" + (i === current ? " is-playing" : "");
      li.innerHTML = `
        <span class="playlist__index">${i === current ? "▶" : i + 1}</span>
        <span class="playlist__info">
          <span class="playlist__name"></span>
          <span class="playlist__by"></span>
        </span>
        <span class="playlist__dur"></span>`;
      li.querySelector(".playlist__name").textContent = t.title || t.src;
      li.querySelector(".playlist__by").textContent = t.artist || "Unknown artist";
      li.addEventListener("click", () => play(i));
      els.playlist.appendChild(li);
    });
  }

  function load(index) {
    const t = tracks[index];
    if (!t) return;
    current = index;
    audio.src = t.src;
    els.trackTitle.textContent = t.title || t.src;
    els.trackArtist.textContent = t.artist || "Unknown artist";
    document.title = `${t.title || t.src} — ymm`;
    renderPlaylist();
  }

  function play(index) {
    if (index != null && index !== current) load(index);
    if (current < 0 && tracks.length) load(0);
    audio.play().catch((err) => setStatus(`Playback blocked: ${err.message}`, true));
  }

  function nextIndex() {
    if (shuffle && tracks.length > 1) {
      let n;
      do { n = Math.floor(Math.random() * tracks.length); } while (n === current);
      return n;
    }
    return current + 1 < tracks.length ? current + 1 : (repeat ? 0 : -1);
  }

  function prevIndex() {
    // Restart current track if more than 3s in, else go to previous.
    if (audio.currentTime > 3) return current;
    if (shuffle && tracks.length > 1) return nextIndex();
    return current - 1 >= 0 ? current - 1 : tracks.length - 1;
  }

  function playNext() {
    const n = nextIndex();
    if (n < 0) { setStatus("End of playlist"); return; }
    play(n);
  }

  // --- Tap feedback (ripple + pop) --------------------------------------
  // Spawn a ripple from the pointer position on any button / playlist row.
  const prefersReducedMotion =
    window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function spawnRipple(target, x, y) {
    const rect = target.getBoundingClientRect();
    const size = Math.max(rect.width, rect.height);
    const ripple = document.createElement("span");
    ripple.className = "ripple";
    ripple.style.width = ripple.style.height = `${size}px`;
    ripple.style.left = `${x - rect.left - size / 2}px`;
    ripple.style.top = `${y - rect.top - size / 2}px`;
    ripple.addEventListener("animationend", () => ripple.remove());
    target.appendChild(ripple);
  }

  document.addEventListener("pointerdown", (e) => {
    if (prefersReducedMotion) return;
    const target = e.target.closest(".controls__btn, .playlist__item");
    if (!target) return;
    spawnRipple(target, e.clientX, e.clientY);
    if (target.classList.contains("controls__btn")) {
      // Pop the button back out once the press is released.
      document.addEventListener("pointerup", () => {
        target.classList.remove("is-pressed");
        void target.offsetWidth; // reflow so rapid taps restart the animation
        target.classList.add("is-pressed");
      }, { once: true });
    }
  });
  document.addEventListener("animationend", (e) => {
    if (e.animationName === "btn-pop") e.target.classList.remove("is-pressed");
  });

  // --- Controls ---------------------------------------------------------
  els.playBtn.addEventListener("click", () => {
    if (audio.paused) play();
    else audio.pause();
  });
  els.nextBtn.addEventListener("click", playNext);
  els.prevBtn.addEventListener("click", () => play(prevIndex()));
  els.shuffleBtn.addEventListener("click", () => {
    shuffle = !shuffle;
    els.shuffleBtn.classList.toggle("is-active", shuffle);
  });
  els.repeatBtn.addEventListener("click", () => {
    repeat = !repeat;
    els.repeatBtn.classList.toggle("is-active", repeat);
  });
  els.volume.addEventListener("input", () => { audio.volume = Number(els.volume.value); });

  els.seek.addEventListener("input", () => { seeking = true; });
  els.seek.addEventListener("change", () => {
    if (audio.duration) audio.currentTime = (Number(els.seek.value) / 100) * audio.duration;
    seeking = false;
  });

  // --- Audio events -----------------------------------------------------
  audio.addEventListener("play", () => { els.playBtn.textContent = "⏸"; els.playBtn.setAttribute("aria-label", "Pause"); });
  audio.addEventListener("pause", () => { els.playBtn.textContent = "▶"; els.playBtn.setAttribute("aria-label", "Play"); });
  audio.addEventListener("loadedmetadata", () => { els.durTime.textContent = fmt(audio.duration); });
  audio.addEventListener("timeupdate", () => {
    els.curTime.textContent = fmt(audio.currentTime);
    if (!seeking && audio.duration) els.seek.value = (audio.currentTime / audio.duration) * 100;
  });
  // Continuous playback: advance when a track ends.
  audio.addEventListener("ended", () => {
    if (repeat && !shuffle && tracks.length === 1) { audio.currentTime = 0; audio.play(); return; }
    playNext();
  });
  audio.addEventListener("error", () => {
    if (audio.src) setStatus(`Could not load: ${tracks[current]?.src || audio.src}`, true);
  });

  // Keyboard: space toggles play/pause, arrows skip.
  document.addEventListener("keydown", (e) => {
    if (e.target.tagName === "INPUT") return;
    if (e.code === "Space") { e.preventDefault(); audio.paused ? play() : audio.pause(); }
    else if (e.code === "ArrowRight") playNext();
    else if (e.code === "ArrowLeft") play(prevIndex());
  });

  // --- Bootstrap --------------------------------------------------------
  async function init() {
    setStatus("Loading playlist…");
    try {
      const res = await fetch("playlist.json", { cache: "no-cache" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      tracks = Array.isArray(data) ? data : (data.tracks || []);
      if (!tracks.length) { setStatus("playlist.json has no tracks. Upload some mp3s!", true); return; }
      renderPlaylist();
      load(0);
      setStatus(`${tracks.length} track${tracks.length === 1 ? "" : "s"} loaded`);
    } catch (err) {
      setStatus(`Failed to load playlist.json: ${err.message}`, true);
    }
  }

  init();
})();
