/* Townloader site motion. 시계는 GSAP ticker 하나만 쓴다 (Lenis, ScrollTrigger, 물결 링 모두). */
(function () {
  const root = document.documentElement;
  const motion = root.classList.contains('js-motion');
  const hasGsap = typeof window.gsap !== 'undefined';

  setupFilm();

  if (!hasGsap) { root.classList.add('intro-done'); return; }
  const gsap = window.gsap;
  if (window.ScrollTrigger) gsap.registerPlugin(window.ScrollTrigger);
  const ST = window.ScrollTrigger;
  const ease = 'expo.out';

  /* ---------- smooth scroll ---------- */
  let lenis = null;
  if (motion && window.Lenis) {
    lenis = new window.Lenis({ autoRaf: false, lerp: 0.12 });
    lenis.on('scroll', () => ST && ST.update());
    gsap.ticker.add((t) => lenis.raf(t * 1000));
    gsap.ticker.lagSmoothing(0);
  }
  document.querySelectorAll('a[href^="#"]').forEach((a) => {
    a.addEventListener('click', (e) => {
      const id = a.getAttribute('href');
      const target = id.length > 1 && document.querySelector(id);
      if (!target) return;
      e.preventDefault();
      if (lenis) lenis.scrollTo(target, { offset: 0, duration: 1.2 });
      else target.scrollIntoView();
      target.setAttribute('tabindex', '-1');
      target.focus({ preventScroll: true });
    });
  });

  /* ---------- bar: 내려갈 땐 비켜서고 올라오면 돌아온다 ---------- */
  let lastY = 0;
  const onScrollY = (y) => {
    root.classList.toggle('is-scrolled', y > 8);
    if (Math.abs(y - lastY) < 4) return;
    root.classList.toggle('bar-away', y > 200 && y > lastY && !document.querySelector('.bar:focus-within'));
    lastY = y;
  };
  if (lenis) lenis.on('scroll', ({ scroll }) => onScrollY(scroll));
  else if (ST) ST.create({ start: 0, end: 'max', onUpdate: () => onScrollY(window.scrollY) });

  /* ---------- hero intro ---------- */
  if (motion) {
    const tl = gsap.timeline({ defaults: { ease }, onComplete: () => root.classList.add('intro-done') });
    // CSS가 숨김용 translateY를 걸어 두므로 y도 0으로 함께 지정한다 (GSAP이 그 값을 y로 읽는다).
    tl.fromTo('.hero .line__in', { y: 0, yPercent: 108 }, { y: 0, yPercent: 0, duration: 1.1, stagger: 0.08 })
      .fromTo('[data-intro-film]', { y: 40 }, { y: 0, duration: 1.1 }, 0.2);
    // CSS 숨김과 GSAP 시작값이 겹치는 동안 깜빡이지 않도록 클래스는 타임라인 첫 프레임 이후에 뗀다.
    gsap.delayedCall(0.05, () => root.classList.add('intro-done'));
  } else {
    root.classList.add('intro-done');
  }

  /* ---------- 히어로 설명: 링크 → AI → 네 갈래 결과를 차례로 보여 주는 루프 ---------- */
  const explain = document.querySelector('[data-explain]');
  if (explain && motion && ST) {
    const q = (sel) => explain.querySelector(sel);
    const nodes = [...explain.querySelectorAll('.node')];
    const outs = [...explain.querySelectorAll('.out')];
    const branches = [...explain.querySelectorAll('.branch path')];
    const conn = q('.conn');
    const branchVisible = () => getComputedStyle(q('.branch')).display !== 'none';
    const setOn = (list, i) => list.forEach((el, k) => el.classList.toggle('is-on', k === i));
    const loop = gsap.timeline({ repeat: -1, repeatDelay: 0.6, defaults: { ease }, paused: true });
    loop
      .set(conn, { '--dot': 0 })
      .set(branches, { strokeDashoffset: 1 })
      .set(outs, { opacity: 0.35 })
      .set(q('.ic-hl'), { scaleX: 0, transformOrigin: '0% 50%' })
      .set(q('.ic-scan'), { y: 0, opacity: 0 })
      .set(q('.ic-pin'), { y: -12, opacity: 0 })
      .set(q('.ic-sum'), { scaleX: 0, transformOrigin: '0% 50%' })
      .set(q('.ic-star'), { scale: 0.4, transformOrigin: '50% 50%' })
      .call(() => { setOn(nodes, 0); setOn(outs, -1); })
      .fromTo(q('.ic-link-a'), { x: -3 }, { x: 0, duration: 0.6, ease: 'back.out(2.2)' }, 0)
      .fromTo(q('.ic-link-b'), { x: 3 }, { x: 0, duration: 0.6, ease: 'back.out(2.2)' }, 0)
      .fromTo(q('.ic-link-bar'), { scaleX: 0, transformOrigin: '50% 50%' }, { scaleX: 1, duration: 0.35 }, 0.25)
      .to(conn, { '--dot': 1, duration: 0.7, ease: 'power2.inOut' }, 0.7)
      .call(() => setOn(nodes, 1), null, 1.35)
      .to(q('.ic-scan'), { opacity: 1, duration: 0.15 }, 1.35)
      .to(q('.ic-scan'), { y: 28, duration: 0.8, ease: 'power1.inOut' }, 1.35)
      .to(q('.ic-scan'), { opacity: 0, duration: 0.2 }, 2.0)
      .to(q('.ic-hl'), { scaleX: 1, duration: 0.45 }, 1.75);
    // 갈래가 하나씩 뻗고, 닿은 결과가 켜진다 (폰에서는 갈래 선 없이 결과만 차례로).
    const icons = [
      () => gsap.to(q('.ic-pin'), { y: 0, opacity: 1, duration: 0.6, ease: 'back.out(2.4)' }),
      () => gsap.fromTo(q('.ic-arrow'), { y: -6 }, { y: 0, duration: 0.6, ease: 'back.out(2)' }),
      () => gsap.to(q('.ic-sum'), { scaleX: 1, duration: 0.5, ease }),
      () => gsap.to(q('.ic-star'), { scale: 1, duration: 0.6, ease: 'back.out(2.6)' }),
    ];
    outs.forEach((out, i) => {
      const at = 2.25 + i * 0.45;
      loop.to(branches[i], { strokeDashoffset: 0, duration: 0.45, ease: 'power2.out' }, at)
        .to(out, { opacity: 1, duration: 0.3 }, at + (branchVisible() ? 0.3 : 0))
        .call(() => { setOn(outs, i); icons[i](); }, null, at + 0.3);
    });
    loop.call(() => { setOn(nodes, -1); setOn(outs, -1); }, null, 5.6).to({}, { duration: 0.01 }, 5.8);
    ST.create({ trigger: explain, start: 'top bottom', end: 'bottom top', onToggle: (self) => (self.isActive ? loop.play() : loop.pause()) });
  }

  /* ---------- how: 진행도 하나로 캡션, 칩, 핀, 코스, 개수를 함께 움직인다 ---------- */
  const how = document.querySelector('[data-how]');
  if (how && motion && ST) {
    const steps = 6;
    const marks = [...how.querySelectorAll('mark[data-step]')];
    const chips = [...how.querySelectorAll('.chips li[data-step]')];
    const pins = [...how.querySelectorAll('.pin[data-step]')];
    const segs = [...how.querySelectorAll('[data-seg]')];
    const count = how.querySelector('[data-count]');
    const ring = how.querySelector('[data-ring]');
    let found = -1;

    const setFound = (n) => {
      if (n === found) return;
      found = n;
      for (const list of [marks, chips, pins]) list.forEach((el, i) => el.classList.toggle('is-found', i < n));
      count.textContent = String(n);
      if (n > 0) {
        const pin = pins[n - 1];
        ring.style.left = pin.style.getPropertyValue('--x');
        ring.style.top = `calc(${pin.style.getPropertyValue('--y')} - 15px)`;
      }
      ring.style.visibility = n > 0 ? 'visible' : 'hidden';
    };

    const apply = (p) => {
      // 0.06 ~ 0.9 구간에 6곳이 고르게 꽂히고, 각 코스 선은 다음 핀까지 이어진다.
      const s = gsap.utils.clamp(0, steps, gsap.utils.mapRange(0.06, 0.9, 0, steps, p));
      setFound(Math.min(steps, Math.floor(s + 0.0001)));
      segs.forEach((seg, i) => {
        const t = gsap.utils.clamp(0, 1, s - (i + 1));
        seg.style.strokeDashoffset = String(1 - t);
      });
    };
    apply(0);
    ST.create({ trigger: how, start: 'top top', end: 'bottom bottom', invalidateOnRefresh: true, onUpdate: (self) => apply(self.progress) });

    // 쉬는 동안: 마지막 핀에서 물결이 천천히 퍼진다. 화면 밖에서는 멈춘다.
    const idle = gsap.fromTo(ring, { scale: 0.4, opacity: 0.7 }, { scale: 1.8, opacity: 0, duration: 2.2, ease: 'power2.out', repeat: -1, repeatDelay: 0.4, paused: true });
    ST.create({ trigger: how, start: 'top bottom', end: 'bottom top', onToggle: (self) => (self.isActive ? idle.play() : idle.pause()) });
  }

  /* ---------- features: 행 위의 포인터를 따라 실제 앱 화면이 온다 ---------- */
  const features = document.querySelector('[data-features]');
  const preview = features && features.querySelector('[data-preview]');
  const finePointer = matchMedia('(hover: hover) and (pointer: fine)').matches;
  if (preview && finePointer) {
    const img = preview.querySelector('img');
    const x = gsap.quickTo(preview, 'x', { duration: 0.6, ease });
    const y = gsap.quickTo(preview, 'y', { duration: 0.6, ease });
    const rot = gsap.quickTo(preview, 'rotation', { duration: 0.8, ease });
    let lastX = 0; let current = null;
    const show = (row) => {
      if (current === row) return;
      current = row;
      if (row) {
        img.src = row.dataset.shot;
        gsap.to(preview, { autoAlpha: 1, scale: 1, duration: 0.45, ease, overwrite: 'auto' });
      } else {
        gsap.to(preview, { autoAlpha: 0, scale: 0.9, duration: 0.3, ease, overwrite: 'auto' });
      }
    };
    // 설명 글을 가리지 않도록 가로 위치는 오른쪽 세 열에 묶고, 포인터는 살짝만 반영한다.
    const zoneX = (cx) => window.innerWidth * 0.79 + (cx - window.innerWidth / 2) * 0.03;
    const track = (cx, cy) => {
      x(zoneX(cx)); y(cy - 180);
      rot(gsap.utils.clamp(-8, 8, (cx - lastX) * 0.4));
      lastX = cx;
    };
    features.querySelectorAll('.row').forEach((row) => {
      row.addEventListener('pointerenter', (e) => { if (!current) gsap.set(preview, { x: zoneX(e.clientX), y: e.clientY - 180 }); show(row); });
      row.addEventListener('pointermove', (e) => track(e.clientX, e.clientY));
      row.addEventListener('pointerleave', () => show(null));
    });
    // 포인터가 멈춘 채 페이지만 스크롤되면 pointerleave가 오지 않는다. 화면 좌표로 다시 확인한다.
    let px = -1; let py = -1;
    window.addEventListener('pointermove', (e) => { px = e.clientX; py = e.clientY; }, { passive: true });
    const recheck = () => {
      if (!current || px < 0) return;
      const under = document.elementFromPoint(px, py);
      if (!under || !current.contains(under)) show(null);
    };
    if (lenis) lenis.on('scroll', recheck);
    if (ST) ST.create({ start: 0, end: 'max', onUpdate: recheck });
  }

  /* ---------- 섹션 등장: 제목 줄과 행이 한 번 자리를 잡는다 ---------- */
  if (motion && ST) {
    gsap.utils.toArray('.features__title, .statement__line').forEach((el) => {
      gsap.fromTo(el, { y: 60, opacity: 0 }, { y: 0, opacity: 1, duration: 1.1, ease, scrollTrigger: { trigger: el, start: 'top 85%', once: true } });
    });
    gsap.utils.toArray('.row').forEach((row) => {
      gsap.fromTo(row, { y: 30, opacity: 0 }, { y: 0, opacity: 1, duration: 0.9, ease, scrollTrigger: { trigger: row, start: 'top 90%', once: true } });
    });
  }

  /* ---------- 영상 ---------- */
  function setupFilm() {
    const video = document.querySelector('[data-film]');
    if (!video) return;
    const toggle = document.querySelector('[data-film-toggle]');
    const sound = document.querySelector('[data-film-sound]');
    const big = document.querySelector('[data-sound-play]');
    const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (reduce) { video.removeAttribute('autoplay'); video.pause(); }
    const sync = () => {
      toggle.textContent = video.paused ? '재생' : '일시정지';
      toggle.setAttribute('aria-pressed', String(video.paused));
      sound.textContent = video.muted ? '소리 켜기' : '소리 끄기';
      sound.setAttribute('aria-pressed', String(!video.muted));
    };
    toggle.addEventListener('click', () => { video.paused ? video.play() : video.pause(); });
    sound.addEventListener('click', () => { video.muted = !video.muted; if (!video.muted && video.paused) video.play(); sync(); });
    if (big) big.addEventListener('click', () => {
      video.muted = false; video.currentTime = 0; video.play(); sync();
      video.closest('.film').scrollIntoView({ block: 'nearest', behavior: reduce ? 'auto' : 'smooth' });
    });
    ['play', 'pause', 'volumechange'].forEach((ev) => video.addEventListener(ev, sync));
    sync();

    // 화면 밖에서는 멈춘다 (소리를 켜고 보는 중이면 그대로 둔다).
    if ('IntersectionObserver' in window && !reduce) {
      new IntersectionObserver(([entry]) => {
        if (!video.muted) return;
        if (entry.isIntersecting) video.play().catch(() => {}); else video.pause();
      }, { threshold: 0.1 }).observe(video);
    }
  }
})();
