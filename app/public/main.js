const highlight_completed_levels = () => {
  let visible = JSON.parse(localStorage.getItem('visible-levels') || '{}');
  let completed = JSON.parse(localStorage.getItem('completed-levels') || '{}');
  let skipped = JSON.parse(localStorage.getItem('skipped-levels') || '{}');

  for (let key in visible) {
    if (completed[key] == true) {
      $(`#skipped-${ key }`).css('display', 'none');
      $(`#completed-${ key }`).css('display', 'inline-flex');
    } else if(skipped[key] == true) {
      $(`#skipped-${ key }`).css('display', 'inline-flex');
      $(`#completed-${ key }`).css('display', 'none');
    } else {
      $(`#skipped-${ key }`).css('display', 'none');
      $(`#completed-${ key }`).css('display', 'none');
    }
  }
};

const show_playable_levels = () => {
  let visible = JSON.parse(localStorage.getItem('visible-levels') || '{}');

  for (let key in visible) {
    if (visible.hasOwnProperty(key) && visible[key] == true) {
      $(`.sidebar-level-${ key }`).css("display", "block");
    }
  }
};

const complete_level = (id, name, next, skipped = false) => {
  // Update the completed levels with 'true'

  if(skipped) {
    let progress = JSON.parse(localStorage.getItem('skipped-levels') || '{}');
    progress[id] = true;
    localStorage.setItem('skipped-levels', JSON.stringify(progress));

    if(name) {
      toastr.info(`Skipped level: ${ name }`);
    }
  } else {
    let progress = JSON.parse(localStorage.getItem('completed-levels') || '{}');
    progress[id] = true;
    localStorage.setItem('completed-levels', JSON.stringify(progress));

    if(name) {
      toastr.success(`Completed level: ${ name }`);
    }
  }

  // Update the visible levels with the next one
  if(next) {
    let visible = JSON.parse(localStorage.getItem('visible-levels') || '{}');
    visible[next] = true;
    localStorage.setItem('visible-levels', JSON.stringify(visible));
  }

  highlight_completed_levels();
  show_playable_levels();

  // No reason to skip anymore!
  $('#skip').hide();
};

const add_result = (text, cls, icon, scroll_target) => {
  const new_div = $('<div class="status">')
  new_div.text(text);
  new_div.addClass(cls);
  new_div.append(`<i class="fa ${ icon } status-icon"></i>`);

  if(scroll_target) {
    new_div.mouseover(function() {
      scroll_target.addClass("highlight");
    });

    new_div.mouseout(function() {
      scroll_target.removeClass("highlight");
    });

    new_div.click(function() {
      scroll_target[0].scrollIntoView({
        behavior: 'smooth',
        block: 'center'
      });

      let count = 0;
      function blink() {
        if (count < 4) { // Double the times for fadeOut and fadeIn
          scroll_target.fadeOut(200, function() {
            scroll_target.fadeIn(200, blink);
          });
          count++;
        }
      }
      blink();
    });
  }

  $('#results-list').append(new_div);
};

const level_loaded_main = (level) => {
  // Highlight the current level
  $(`#${ level['id'] }`).addClass('current-level');

  // Make it visible forevermore
  let visible = JSON.parse(localStorage.getItem('visible-levels') || '{}');
  visible[level['id']] = true;
  localStorage.setItem('visible-levels', JSON.stringify(visible));

  // Only bother with the 'skip' button if the next level isn't unlocked
  if(level['next'] && !visible[level['next']]) {
    $('#skip').show();
    $('#skip').on('click', () => {
      if(confirm("This will unlock the next level without completing this one! You can always go back later. Are you sure?")) {
        complete_level(level['id'], level['name'], level['next'], true);
      }
    });
  }

  // Enable the next/prev buttons
  if(level['next'] && visible[level['next']]) {
    $('#nextPage').removeClass('disabled');
    $('#nextPage').on('click', () => {
      document.location = `/level/${ level['next'] }`;
    });
  }

  if(level['previous'] && visible[level['previous']]) {
    $('#previousPage').removeClass('disabled');
    $('#previousPage').on('click', () => {
      document.location = `/level/${ level['previous'] }`;
    });
  }

  // Highlight completed levels
  highlight_completed_levels();

  // Show the levels they can work on
  show_playable_levels();

  //document.getElementById("nextPage").addEventListener("click", function() {
  //  document.location = '/level/<%= level['next'] %>';
  //});
};

$(document).ready(() => {
  if ($("#id").length) {
    // Load the level object
    $.getJSON(`/api/levels/${ $("#id").val() }`)
      .done((level) => {
        // Let scripts know the level is loaded, if they want to know
        if(typeof level_loaded === 'function') {
          level_loaded(level);
        }
        level_loaded_main(level);
      })
      .fail((xhr, status, error) => {
        console.error(`Error: ${ error }`);
        console.error(xhr);
        toastr.error(`Error: ${ error }`);
      });
  }

  // Make the clear button work
  $('#clear').on('click', () => {
    if(confirm("Are you sure you want to clear your progress?")) {
      localStorage.removeItem('visible-levels');
      localStorage.removeItem('completed-levels');
      localStorage.removeItem('skipped-levels');
      window.location.href = '/';
    }
  });
});
