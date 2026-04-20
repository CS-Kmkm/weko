$(document).ready(function () {
  $('#step_page').focus();
  $('#activity_locked').hide();
  $('#locked_msg').hide()
  $('#user_locked').hide()

  var guestEmail = $('#current_guest_email').val();

  var get_error_msg = function (jqXHR) {
    if (jqXHR && jqXHR.responseJSON && jqXHR.responseJSON.msg) {
      return jqXHR.responseJSON.msg;
    }
    return 'Server error';
  };

  var unlocks_activity = function (activity_id, locked_value, is_opened, is_force = false) {
    if (guestEmail){
      return ;
    }
    var url = '/workflow/activity/unlocks/' + activity_id;
    var is_ie = /*@cc_on!@*/false || !!document.documentMode;

    var data = JSON.stringify({
      locked_value: locked_value,
      is_opened: is_opened,
      is_force: is_force
    })
    if (is_ie) {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", url, false);
      xhr.send(data);
    } else {
      navigator.sendBeacon(url, data);
    }
    if (locked_value){sessionStorage.removeItem('locked_value');}
    sessionStorage.removeItem('is_opened');
  };

  var unlock_activity = function (activity_id, locked_value, on_done) {
    if (guestEmail) {
      return;
    }
    var url = '/workflow/activity/unlock/' + activity_id;
    var data = {
      locked_value: locked_value
    };

    $.ajax({
      type: 'POST',
      cache: false,
      contentType: 'application/json',
      url: url,
      data: JSON.stringify(data),
      success: function () {
        if (typeof on_done === 'function') {
          on_done(true);
        }
      },
      error: function (jqXHR) {
        if (typeof on_done === 'function') {
          on_done(false, jqXHR);
        }
      },
      complete: function () {
        sessionStorage.removeItem('locked_value');
      }
    });
  };

  var user_unlock_activity = function (activity_id, is_opened, is_force = false, force_activity_id = '', on_done) {
    if (guestEmail) {
      return;
    }
    var url = '/workflow/activity/user_unlock/' + activity_id;

    var data = {
      is_opened: is_opened,
      is_force: is_force,
      force_activity_id: force_activity_id
    };

    $.ajax({
      type: 'POST',
      cache: false,
      contentType: 'application/json',
      url: url,
      data: JSON.stringify(data),
      success: function () {
        if (typeof on_done === 'function') {
          on_done(true);
        }
      },
      error: function (jqXHR) {
        if (typeof on_done === 'function') {
          on_done(false, jqXHR);
        }
      },
      complete: function () {
        sessionStorage.removeItem('is_opened');
      }
    });
  }

  var current_user_email = $('input#current_user_email').val();
  var locked_value = sessionStorage.getItem('locked_value');
  var is_opened = sessionStorage.getItem('is_opened')
  var activity_id = $('input#activity_id_for_lock').val();
  var cur_step = $('input#cur_step_for_lock').val();
  var permission = $('#hide-res-check').text(); // 0: allow, <> 0: deny


  var  csrf_token=$('#csrf_token').val();
  $.ajaxSetup({
    beforeSend: function(xhr, settings) {
       if (!/^(GET|HEAD|OPTIONS|TRACE)$/i.test(settings.type) && !this.crossDomain){
           xhr.setRequestHeader("X-CSRFToken", csrf_token);
       }
    }
  });

  if ('end_action' !== cur_step && permission == 0 && !guestEmail) {
    $.ajax({
      type: "POST",
      cache: false,
      url: '/workflow/activity/user_lock/' + activity_id,
      success: function (result) {
        if (result.err) {
          $('#step_page').hide();
          $('#activity_locked').show();
          $('#user_locked').show();
          $('#user_locked_btn').show();
          var msg = $('#user_locked_msg').text();
          if (result.activity_id) {
            msg = msg.replace('{}', result.activity_id);
          } else {
            msg = msg.replace(' ({})', '');
            msg = msg.replace('（{}）', '');
          }
          $('#user_locked_msg').html(msg);
          $('#user_locked_btn').off('click').on('click', function(){
            $("#action_unlock_activity").modal("show");
            $("#user_lock_modal").css('display','block');
            $('#btn_unlock').off('click').on('click', function () {
              $("#action_unlock_activity").modal("hide");
              user_unlock_activity(activity_id, is_opened, true, result.activity_id, function (success, jqXHR) {
                if (success) {
                  location.reload();
                } else {
                  alert(get_error_msg(jqXHR));
                }
              });
            });
          });
          is_opened=true;
          sessionStorage.setItem('is_opened', is_opened);
        } else {
          is_opened = false
          sessionStorage.setItem('is_opened', is_opened);
        }
      },
      error: function(jqXHR, status){
        alert(jqXHR.responseJSON.msg)
      }
    });
    $.ajax({
      type: "POST",
      cache: false,
      data: {
        locked_value: locked_value
      },
      url: '/workflow/activity/lock/' + activity_id,
      success: function (result) {
        if (result.err) {
          $('#step_page').hide();
          $('#activity_locked').show();
          $('#locked_msg').show()
          var msg = $('#locked_msg').text();
          if (result.locked_by_username) {
            msg = msg.replace('{}', result.locked_by_username);
          } else {
            msg = msg.replace(' ({})', '');
            msg = msg.replace('（{}）', '');
          }
          $('#locked_msg').html(msg);

          if (current_user_email === result.locked_by_email) {
            $("#action_unlock_activity").modal("show");
            $("#lock_modal").css('display','block');
            // handle popup unlock
            $('#btn_unlock').off('click').on('click', function () {
              $("#action_unlock_activity").modal("hide");
              unlock_activity(activity_id, result.locked_value, function (success, jqXHR) {
                if (success) {
                  location.reload();
                } else {
                  alert(get_error_msg(jqXHR));
                }
              });
            });
          }
        } else {
          locked_value = result.locked_value;
          sessionStorage.setItem('locked_value', locked_value);
        }
      },
      error: function(jqXHR, status){
        alert(jqXHR.responseJSON.msg)
      }
    });
  } else if (locked_value) {
    unlock_activity(activity_id, locked_value);
  }

  // start: approval page
  $('#btn-return, #btn-reject, #btn-approval, .save-button, .done-button, .next-button').click(function () {
    locked_value = 0;
  });

  window.addEventListener('beforeunload', function (e) {
    unlocks_activity(activity_id, locked_value, is_opened)
    // イベントをキャンセルする
    // e.preventDefault();
    // Chrome では returnValue を設定する必要がある
    e.returnValue = '';
  });

  window.addEventListener('unload', function (e) {
    unlocks_activity(activity_id, locked_value, is_opened)
    // イベントをキャンセルする
    // e.preventDefault();
    // Chrome では returnValue を設定する必要がある
    // e.returnValue = '';
  });
});
