/* kterm Chrome grab. Injected into the front Chrome tab.
   Ctrl+Shift+K (page focus only) arms the overlay. Click copies a text
   reference to the clipboard. Nothing is typed into a terminal. */
(function () {
  if (window.__ktermGrabInstalled) return;
  if (!document.documentElement) return;

  var BOX_ID = "kterm-grab-box";
  var CATCH_ID = "kterm-grab-catch";
  var TOAST_ID = "kterm-grab-toast";

  function clamp(value, max) {
    var text = String(value || "").replace(/\s+/g, " ").trim();
    if (text.length <= max) return text;
    return text.slice(0, max) + "…";
  }

  function cssEscape(value) {
    if (window.CSS && CSS.escape) return CSS.escape(value);
    return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
  }

  function secret(value) {
    return /(?:api[_-]?key|secret|token|password|authorization)/i.test(String(value || ""));
  }

  function stableClasses(el) {
    if (!el.classList) return [];
    var out = [];
    for (var i = 0; i < el.classList.length && out.length < 2; i++) {
      var cls = el.classList[i];
      if (!cls || cls.length > 48 || secret(cls)) continue;
      if (/^css-[a-z0-9]+$/i.test(cls)) continue;
      out.push(cls);
    }
    return out;
  }

  function part(el) {
    var tag = el.tagName.toLowerCase();
    if (el.id && !secret(el.id)) return tag + "#" + cssEscape(el.id);
    var classes = stableClasses(el);
    if (classes.length) {
      return tag + classes.map(function (cls) { return "." + cssEscape(cls); }).join("");
    }
    return tag;
  }

  function unique(selector) {
    try { return document.querySelectorAll(selector).length === 1; }
    catch (e) { return false; }
  }

  function selector(el) {
    var parts = [];
    var current = el;
    while (current && current.nodeType === 1 && current !== document.body && parts.length < 8) {
      var bit = part(current);
      parts.unshift(bit);
      var built = parts.join(" > ");
      if (unique(built)) return clamp(built, 400);
      current = current.parentElement;
    }
    return clamp(parts.join(" > ") || (el.tagName || "").toLowerCase(), 400);
  }

  function ancestors(el) {
    var parts = [];
    var current = el.parentElement;
    while (current && current !== document.documentElement && parts.length < 6) {
      if (current === document.body) break;
      parts.unshift(part(current));
      current = current.parentElement;
    }
    return parts.join(" > ");
  }

  function sourceOf(el) {
    var current = el;
    while (current && current !== document.body) {
      if (current.getAttribute) {
        var astro = current.getAttribute("data-astro-source");
        if (astro && !secret(astro)) return astro;
      }
      current = current.parentElement;
    }
    return reactMeta(el).sourceFile;
  }

  function reactMeta(el) {
    var empty = { react: "", sourceFile: "" };
    try {
      var keys = Object.keys(el);
      var fiber = null;
      for (var i = 0; i < keys.length; i++) {
        if (keys[i].indexOf("__reactFiber$") === 0 || keys[i].indexOf("__reactInternalInstance$") === 0) {
          fiber = el[keys[i]];
          break;
        }
      }
      if (!fiber) return empty;
      var names = [];
      var source = "";
      var depth = 0;
      while (fiber && depth < 25) {
        var type = fiber.type || fiber.elementType;
        var name = type && (type.displayName || type.name);
        if (name && names.indexOf(name) === -1 && names.length < 5 &&
            !/^(div|span|Fragment|Suspense|Provider)$/.test(name)) {
          names.push(name);
        }
        var debug = fiber._debugSource;
        if (!source && debug && debug.fileName && debug.lineNumber) {
          source = String(debug.fileName).replace(/^webpack:\/\/\/\.?\//, "") + ":" + debug.lineNumber;
        }
        fiber = fiber.return;
        depth++;
      }
      return {
        react: names.reverse().map(function (n) { return "<" + n + ">"; }).join(" "),
        sourceFile: secret(source) ? "" : source
      };
    } catch (e) {
      return empty;
    }
  }

  function snippet(el) {
    var text = (el.innerText || el.textContent || "").replace(/\s+/g, " ").trim();
    return clamp(text, 400);
  }

  function html(el) {
    var raw = el.outerHTML || "";
    raw = raw.replace(/\s(value|placeholder)="[^"]*"/gi, "");
    return clamp(raw, 800);
  }

  function accessibleName(el) {
    var labelled = el.getAttribute && el.getAttribute("aria-label");
    if (labelled && !secret(labelled)) return clamp(labelled, 120);
    if (el.labels && el.labels.length && el.labels[0].innerText) {
      return clamp(el.labels[0].innerText, 120);
    }
    return "";
  }

  function describe(el) {
    var react = reactMeta(el);
    var rect = el.getBoundingClientRect();
    var style = window.getComputedStyle(el);
    var lines = [];
    lines.push("Attached browser context from " + location.href);
    lines.push("");
    lines.push("Selected element:");
    lines.push((el.tagName || "").toLowerCase());
    var name = accessibleName(el);
    if (name) lines.push('Accessible name: "' + name + '"');
    var role = (el.getAttribute && el.getAttribute("role")) || "";
    if (role && !secret(role)) lines.push("Role: " + role);
    lines.push("Selector: " + selector(el));
    var source = sourceOf(el);
    if (source) lines.push("Source: " + source);
    if (react.react) lines.push("React: " + react.react);
    lines.push("Dimensions: " + Math.round(rect.width) + "x" + Math.round(rect.height));
    lines.push("");
    var text = snippet(el);
    if (text) {
      lines.push("Text content:");
      lines.push(text);
      lines.push("");
    }
    var bits = [];
    if (style.display && style.display !== "inline") bits.push("display: " + style.display);
    if (style.fontSize) bits.push("font-size: " + style.fontSize);
    if (style.color) bits.push("color: " + style.color);
    if (style.backgroundColor && style.backgroundColor !== "rgba(0, 0, 0, 0)") {
      bits.push("background: " + style.backgroundColor);
    }
    if (bits.length) {
      lines.push("Computed styles:");
      bits.forEach(function (bit) { lines.push("  " + bit); });
      lines.push("");
    }
    var markup = html(el);
    if (markup) {
      lines.push("HTML:");
      lines.push(markup);
      lines.push("");
    }
    var path = ancestors(el);
    if (path) lines.push("Ancestor path: " + path);
    return lines.join("\n").trim();
  }

  function copyText(text) {
    var area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.left = "-9999px";
    document.documentElement.appendChild(area);
    area.select();
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
    area.remove();
    return ok;
  }

  function toast(message) {
    var old = document.getElementById(TOAST_ID);
    if (old) old.remove();
    var node = document.createElement("div");
    node.id = TOAST_ID;
    node.textContent = message;
    node.style.cssText = [
      "position:fixed", "left:16px", "bottom:16px", "z-index:2147483647",
      "background:#1a1a2e", "color:#fff", "padding:8px 12px",
      "border-radius:8px", "font:13px/1.3 -apple-system,sans-serif",
      "box-shadow:0 6px 24px rgba(0,0,0,.35)"
    ].join(";");
    document.documentElement.appendChild(node);
    setTimeout(function () { if (node.parentNode) node.remove(); }, 1400);
  }

  var armed = false;

  function disarm() {
    armed = false;
    [BOX_ID, CATCH_ID].forEach(function (id) {
      var node = document.getElementById(id);
      if (node) node.remove();
    });
  }

  function targetAt(event) {
    var catcher = document.getElementById(CATCH_ID);
    if (catcher) catcher.style.visibility = "hidden";
    var el = document.elementFromPoint(event.clientX, event.clientY);
    if (catcher) catcher.style.visibility = "visible";
    if (!el || el.id === BOX_ID || el.id === TOAST_ID) return null;
    return el;
  }

  function moveBox(el) {
    var box = document.getElementById(BOX_ID);
    if (!box) return;
    var rect = el.getBoundingClientRect();
    box.style.left = rect.left + "px";
    box.style.top = rect.top + "px";
    box.style.width = Math.max(rect.width, 2) + "px";
    box.style.height = Math.max(rect.height, 2) + "px";
  }

  function arm() {
    if (armed) {
      disarm();
      return;
    }
    armed = true;
    var box = document.createElement("div");
    box.id = BOX_ID;
    box.style.cssText = [
      "position:fixed", "pointer-events:none", "z-index:2147483647",
      "border:2px solid #bc52ee", "background:rgba(188,82,238,0.18)",
      "box-sizing:border-box"
    ].join(";");
    var catcher = document.createElement("div");
    catcher.id = CATCH_ID;
    catcher.style.cssText = "position:fixed;inset:0;z-index:2147483646;cursor:crosshair;background:transparent;";
    catcher.addEventListener("mousemove", function (event) {
      var el = targetAt(event);
      if (el) moveBox(el);
    });
    catcher.addEventListener("click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      var el = targetAt(event);
      disarm();
      if (!el) return;
      var text = describe(el);
      if (copyText(text)) {
        toast("Copied element reference");
      } else if (window.__ktermGrab) {
        window.__ktermGrab.result = "KTERM:" + text;
        toast("Copied element reference");
      }
    }, true);
    catcher.addEventListener("contextmenu", function (event) {
      event.preventDefault();
      disarm();
    });
    document.documentElement.appendChild(box);
    document.documentElement.appendChild(catcher);
  }

  window.addEventListener("keydown", function (event) {
    if (event.repeat) return;
    if (event.key === "Escape" && armed) {
      event.preventDefault();
      disarm();
      return;
    }
    var key = event.key === "K" || event.key === "k" || event.code === "KeyK";
    if (!(event.ctrlKey && event.shiftKey && !event.metaKey && !event.altKey && key)) return;
    event.preventDefault();
    event.stopPropagation();
    arm();
  }, true);

  window.__ktermGrab = window.__ktermGrab || { result: "" };
  window.__ktermGrabInstalled = true;
})();
