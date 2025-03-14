const highlight_completed_levels = () => {
  let progress = JSON.parse(localStorage.getItem('progress') || '{}');

  for (let key in progress) {
    if (progress.hasOwnProperty(key) && progress[key] == true) {
      $(`#completed-${ key }`).css('display', 'inline-flex');
    }
  }
};

const complete_level = (id, name) => {
  let progress = JSON.parse(localStorage.getItem('progress') || '{}');
  progress[id] = true;
  localStorage.setItem('progress', JSON.stringify(progress));

  if(name) {
    toastr.success(`Completed level: ${ name }`);
  }
  highlight_completed_levels();
};

let level;
$(document).ready(() => {
  // Load the level object
  $.getJSON(`/api/levels/${ $("#id").val() }`)
    .done((data) => {
      level = data;
    })
    .fail((xhr, status, error) => {
      console.error(`Error: ${ error }`);
      toastr.error(`Error: ${ error }`);
    });

  // Highlight completed levels
  highlight_completed_levels();

  $('#clear').on('click', () => {
    if(confirm("Are you sure you want to clear your progress?")) {
      localStorage.removeItem(`progress`);
      location.reload();
    }
  });
});
