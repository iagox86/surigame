// This code handles suricata-y stuff
const level_loaded = (level) => {
  // Note: can't use the level variable yet, since it's not populated
  let rule = localStorage.getItem(`rule-${ level['id'] }`);
  if(rule) {
    console.log('Loaded rule from localStorage!');
    $('#rule').val(rule);
  }

  $('#reset').on('click', () => {
    if (confirm("Are you sure you want to reset?")) {
      $('#rule').val(level['base_rule']);
      localStorage.removeItem(`rule-${ level['id'] }`);
    }
  });

  $('#send').on('click', () => {
    $('#loadingIndicator').show();
    $('#results-list').empty();
    $.ajax({
      type: 'POST',
      url: `/api/suricata/${ level['id'] }`,
      data: JSON.stringify({
        'rule': $('#rule').val(),
      }),
      contentType: 'application/json; charset=utf-8',
      dataType: 'json',
      success: function(data) {
        $('#loadingIndicator').hide();
        $('#results-list').empty();
        for (const result of data['results']) {
          let target = $(`#rule`);
          if(result['id']) {
            target = $(`#request-${ result['id'] }`);
          }

          if(result['type'] == 'success') {
            add_result(result['message'], result['type'], 'fa-check-circle', target);
          } else if(result['type'] == 'miss') {
            add_result(result['message'], result['type'], 'fa-exclamation-circle', target);
          } else if(result['type'] == 'overmatch') {
            add_result(result['message'], result['type'], 'fa-exclamation-circle', target);
          } else {
            add_result(result['message'], result['type'], 'fa-times-circle', target);
          }
        }

        // Show it, if it's not already shown
        $('#results').fadeIn(500);

        // Scroll to the results
        $('#results')[0].scrollIntoView({
          behavior: 'smooth',
          block: 'center'
        });

        if(data['completed'] == true) {
          complete_level(level['id'], level['name'], level['next']);
        }
      },
      error: function(xhr, status, error) {
        $('#loadingIndicator').hide();
        console.log(xhr);
        if(xhr.responseJSON) {
          if(xhr.responseJSON.error) {
            toastr.error(`Error: ${ xhr.responseJSON.error }`);
            console.error(`Error: ${ error }`);
            console.error(xhr.responseJSON);
          } else {
            toastr.error(`Unknown error: ${ error }: ${ xhr.responseJSON }`);
            console.error(`Unknown error: ${ error }: ${ xhr.responseJSON }`);
          }
        } else {
          toastr.error(`Unknown error: ${ error }`);
          console.error(`Unknown error: ${ error }`);
        }
      }
    });
  });

  // Save the rule to localStorage every keypress
  $('#rule').on('keyup', () => {
    localStorage.setItem(`rule-${ level['id'] }`, $('#rule').val());
  });
};
