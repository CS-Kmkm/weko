Workflow Activity Lock Handling
==============================

Overview
--------

This document summarizes the workflow activity lock issue that caused users to be blocked with messages such as:

- Permission required
- One user cannot open multiple activities simultaneously.
- Already have another activity open (...).

It also describes the implemented fixes and the operational recovery procedure.

Symptoms
--------

- A user can no longer open workflow activities.
- The screen keeps showing that another activity is already open.
- Force Unlock appears to run, but the lock state remains.

Root Causes
-----------

1. Stale user lock cache could remain in Redis after browser/session interruption.
2. Force Unlock behavior in frontend was fire-and-forget oriented, so failures were not visible to users.
3. User unlock payload values (``is_opened``, ``is_force``) could arrive as strings, and were not robustly normalized before lock-deletion checks.

Implemented Fixes
-----------------

Frontend (reliable unlock flow)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

- Updated workflow lock scripts to use explicit AJAX completion handling for unlock actions.
- Page reload is now executed after unlock request completion handling.
- Unlock failure now surfaces an error message.
- Duplicate click handlers are prevented with ``off('click').on('click', ...)``.

Backend (robust lock deletion)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

- Added boolean normalization for ``is_opened`` and ``is_force`` before evaluating unlock conditions.
- Prevented unlock-condition mismatch when request values are provided as strings (e.g. ``"true"``, ``"false"``).

Backend (stale lock auto-recovery)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

- In user lock checks, stale ``workflow_userlock_activity_<user_id>`` cache is automatically removed when:

  - referenced activity no longer exists, or
  - referenced activity is already closed (``C``, ``P``, ``F``).

- This cleanup is applied in both:

  - ``GET /workflow/activity/user_lock``
  - ``POST /workflow/activity/user_lock/<activity_id>``

Operational Recovery Procedure
------------------------------

If a lock issue is suspected in an environment, verify and clear lock keys from the running web container:

.. code-block:: bash

   docker compose -f docker-compose2.yml exec -T web bash -lc \
     "source /home/invenio/.virtualenvs/invenio/bin/activate && \
      invenio shell -c \"from invenio_cache import current_cache; \
  user_id='1'; activity_id='A-YYYYMMDD-NNNNN'; \
  print(current_cache.get('workflow_userlock_activity_' + user_id)); \
  print(current_cache.get('workflow_locked_activity_' + activity_id))\""

.. code-block:: bash

   docker compose -f docker-compose2.yml exec -T web bash -lc \
     "source /home/invenio/.virtualenvs/invenio/bin/activate && \
      invenio shell -c \"from invenio_cache import current_cache; \
  user_id='1'; activity_id='A-YYYYMMDD-NNNNN'; \
  current_cache.delete('workflow_userlock_activity_' + user_id); \
  current_cache.delete('workflow_locked_activity_' + activity_id)\""

After updating source code, rebuild static assets and restart services:

.. code-block:: bash

   docker compose -f docker-compose2.yml exec -T web bash -lc \
     "source /home/invenio/.virtualenvs/invenio/bin/activate && \
      invenio assets build && invenio collect -v"

   docker compose -f docker-compose2.yml restart web nginx

Changed Files
-------------

- ``modules/weko-workflow/weko_workflow/static/js/weko_workflow/lock_activity.js``
- ``modules/weko-workflow/weko_workflow/utils.py``
- ``modules/weko-workflow/weko_workflow/views.py``
- ``modules/weko-workflow/weko_workflow/templates/weko_workflow/lock_activity.html``
- ``modules/weko-workflow/tests/test_utils.py``
- ``modules/weko-workflow/tests/test_views.py``
