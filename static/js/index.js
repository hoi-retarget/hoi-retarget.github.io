// HOI-Retarget project page. No analytics, no third-party trackers — the page
// must not phone home anywhere that could deanonymise the submission.
(function () {
  'use strict';

  // --- clip switchers -------------------------------------------------------
  // Each .clip-group holds a row of buttons and one <video> per clip. Only the
  // selected clip ever gets a src, so a page with 17 clips downloads one.
  function hydrate(group) {
    var buttons = group.querySelectorAll('.clip-tabs button');
    var videos = group.querySelectorAll('video[data-src]');

    function select(index) {
      buttons.forEach(function (b, i) {
        b.setAttribute('aria-selected', String(i === index));
      });
      videos.forEach(function (v, i) {
        if (i !== index) {
          v.pause();
          v.hidden = true;
          return;
        }
        v.hidden = false;
        if (!v.getAttribute('src')) v.setAttribute('src', v.dataset.src);
        var p = v.play();
        if (p && p.catch) p.catch(function () { /* autoplay blocked; fine */ });
      });
    }

    buttons.forEach(function (b, i) {
      b.addEventListener('click', function () { select(i); });
    });
    select(0);
  }

  // --- viewport-gated playback ---------------------------------------------
  // Load and play a video only while it is on screen. Keeps a page full of
  // loops from saturating the connection or the decoder.
  var observer = 'IntersectionObserver' in window
    ? new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          var v = entry.target;
          if (v.hidden) return;
          if (entry.isIntersecting) {
            if (!v.getAttribute('src') && v.dataset.src) v.setAttribute('src', v.dataset.src);
            var p = v.play();
            if (p && p.catch) p.catch(function () {});
          } else {
            v.pause();
          }
        });
      }, { rootMargin: '200px 0px', threshold: 0.15 })
    : null;

  document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.clip-group').forEach(hydrate);

    // Standalone videos (not inside a switcher) load eagerly on approach.
    document.querySelectorAll('video.panel-video').forEach(function (v) {
      if (observer) observer.observe(v);
      else if (v.dataset.src && !v.getAttribute('src')) v.setAttribute('src', v.dataset.src);
    });
  });
})();
