function clickedSection(event) {
  var section = event.currentTarget;
  section.classList.add("selected");
  section.parentElement.classList.add("chosen");
  
  section.querySelectorAll("iframe").forEach(resizeIframe);
  
  updateSectionListeners("remove");
}

function updateSectionListeners(action) {
  document.querySelectorAll("section").forEach(function (e) {
    e[action + "EventListener"]("click", clickedSection, false);
    e.classList.add("ready");
  });
}

updateSectionListeners("add");

function resizeIframe(frame) {
  var doc = frame.contentDocument || frame.contentWindow.document;
  if (doc.readyState === 'complete') {
    var height = frame.contentDocument.body.scrollHeight;
    // Add 25 pixels for possible scrollbar at bottom
    height += 25;
    frame.style.height = height + 'px';
  } else {
    frame.addEventListener('load', function() {
      resizeIframe(frame);
    }, false);
  }
}
