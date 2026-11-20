// Draws the night span on the home page: a fresh noise trace on every visit
// (the static one in the HTML is the no-script fallback), a single left-to-right
// draw, and a pointer readout of the time under the cursor.
(function () {
  var fig = document.querySelector(".night");
  if (!fig) return;

  var START_MIN = 22 * 60 + 42; // 10:42 PM
  var TOTAL_MIN = 7 * 60 + 37; // 7h 37m
  // The band is drawn to scale: the 5 s fade-in is instant at this size and
  // the final minute is TAIL units of 1000. The level holds steady between.
  var W = 1000, MID = 80, HALF = 44, STEP = 3, TAIL = 1000 / TOTAL_MIN;

  function envelope(x) {
    if (x > W - TAIL) { var v = (W - x) / TAIL; return v * v; }
    return 1;
  }

  function trace() {
    // Keep bars about 3 screen pixels apart at any width.
    var w = fig.clientWidth || W;
    var step = Math.max(STEP, (3 * W) / w);
    var d = "";
    for (var x = 1; x < W; x += step) {
      var h = HALF * envelope(x) * (0.9 + 0.1 * Math.random());
      if (h < 0.6) h = 0.6;
      d += "M" + x.toFixed(1) + " " + (MID - h).toFixed(1) + "V" + (MID + h).toFixed(1);
    }
    return d;
  }

  var path = fig.querySelector(".trace");
  if (path) path.setAttribute("d", trace());

  requestAnimationFrame(function () {
    requestAnimationFrame(function () { fig.classList.add("is-drawn"); });
  });

  // Pointer readout.
  var plot = fig.querySelector(".night-plot");
  var cursor = fig.querySelector(".cursor");
  var label = cursor && cursor.querySelector("span");
  if (!plot || !cursor || !label) return;

  function clock(min) {
    var m = Math.round(min) % 1440;
    var h = Math.floor(m / 60), mm = m % 60;
    var ap = h >= 12 ? "PM" : "AM";
    h = h % 12 || 12;
    return h + ":" + (mm < 10 ? "0" : "") + mm + " " + ap;
  }
  function span(min) {
    var h = Math.floor(min / 60), m = Math.round(min % 60);
    return h ? h + "h " + m + "m in" : m + "m in";
  }

  plot.addEventListener("pointermove", function (e) {
    if (e.pointerType === "touch") return;
    var r = plot.getBoundingClientRect();
    var f = Math.max(0, Math.min(1, (e.clientX - r.left) / r.width));
    var min = f * TOTAL_MIN;
    cursor.style.left = f * 100 + "%";
    cursor.classList.toggle("flip", f > 0.78);
    label.innerHTML = clock(START_MIN + min) + " <em>· " + span(min) + "</em>";
    plot.classList.add("is-hover");
  });
  plot.addEventListener("pointerleave", function () { plot.classList.remove("is-hover"); });
})();
