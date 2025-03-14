// This code handles suricata-y stuff
$(document).ready(() => {
  // Note: can't use the level variable yet, since it's not populated
  let rule = localStorage.getItem(`rule-${ $("#id").val() }`);
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
          const new_div = $('<div class="status">')
          new_div.text(result['message']);
          new_div.addClass(result['type']);

          console.log(result['type']);
          if(result['type'] == 'success') {
            new_div.append('<i class="fa fa-check-circle status-icon"></i>');
          } else if(result['type'] == 'miss') {
            new_div.append('<i class="fa fa-exclamation-circle status-icon"></i>');
          } else if(result['type'] == 'overmatch') {
            new_div.append('<i class="fa fa-exclamation-circle status-icon"></i>');
          } else {
            new_div.append('<i class="fa fa-times-circle status-icon"></i>');
          }

          let target = $(`#rule`);
          if(result['id']) {
            target = $(`#request-${ result['id'] }`);
          }

          new_div.mouseover(function() {
            target.addClass("highlight");
          });

          new_div.mouseout(function() {
            target.removeClass("highlight");
          });

          new_div.click(function() {
            target[0].scrollIntoView({
              behavior: 'smooth',
              block: 'center'
            });

            let count = 0;
            function blink() {
              if (count < 4) { // Double the times for fadeOut and fadeIn
                target.fadeOut(200, function() {
                  target.fadeIn(200, blink);
                });
                count++;
              }
            }
            blink();
          });

          $('#results-list').append(new_div);
        }
        //$('#response').html(hljs.highlight(atob(data['response']), { language: 'html' }).value);
        //
        if(data['completed'] == true) {
          complete_level(level['id'], level['name']);
        }
        console.log('Response received:', data);
      },
      error: function(xhr, status, error) {
        $('#loadingIndicator').hide();
        toastr.error(`Error: ${ error }`);
        console.error(`Error: ${ error }`);
      }
    });
  });

  // Save the rule to localStorage every keypress
  $('#rule').on('keyup', () => {
    localStorage.setItem(`rule-${ level['id'] }`, $('#rule').val());
  });
});
