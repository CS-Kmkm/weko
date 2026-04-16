import pytest
import copy
import os
import json
from datetime import datetime
from unittest.mock import MagicMock, patch

from weko_itemtypes_ui.views import get_itemtypes, replace_mapping_version

# def itemtype_mapping(ItemTypeID=0):
# def get_itemtypes():
#     def convert(item):

# pytest -v --cov=weko_itemtypes_ui tests/test_views.py::test_replace_mapping_version --cov-branch --cov-report=term --cov-report=html --cov-config=tox.ini --basetemp=/code/modules/weko-itemtypes-ui/.tox/c1/tmp
# def replace_mapping_version(jp_key):
@pytest.mark.parametrize(
    "jp_key, return_key_value",
    [
        ("publisher_jpcoar", "publisher(jpcoar)"),
        ("publisher", "publisher(dc)"),
        ("date_dcterms", "date(dcterms)"),
        ("date", "date(datacite)"),
        ("versiontype", "version(oaire)"),
        ("version", "version(datacite)"),
        ("test", "test")
    ]
)
def test_replace_mapping_version(app, jp_key, return_key_value):
    if jp_key == "publisher_jpcoar":
        assert replace_mapping_version(jp_key) == return_key_value

    elif jp_key == "publisher":
        assert replace_mapping_version(jp_key) == return_key_value

    elif jp_key == "date_dcterms":
        assert replace_mapping_version(jp_key) == return_key_value

    elif jp_key == "date":
        assert replace_mapping_version(jp_key) == return_key_value

    elif jp_key == "versiontype":
        assert replace_mapping_version(jp_key) == return_key_value

    elif jp_key == "version":
        assert replace_mapping_version(jp_key) == return_key_value

    else:
        assert replace_mapping_version(jp_key) == return_key_value


def test_get_itemtypes_skips_orphan_item_type_name(app):
    orphan_item_type_name = MagicMock()
    orphan_item_type_name.id = 1
    orphan_item_type_name.name = "orphan"
    orphan_item_type_name.item_type.first.return_value = None

    valid_item_type = MagicMock()
    valid_item_type.id = 2
    valid_item_type.tag = 1
    valid_item_type.harvesting_type = False
    valid_item_type.is_deleted = False

    valid_item_type_name = MagicMock()
    valid_item_type_name.id = 2
    valid_item_type_name.name = "valid"
    valid_item_type_name.item_type.first.return_value = valid_item_type

    with app.test_request_context('/itemtypes/lastest?type=normal_type'):
        with patch(
            'weko_itemtypes_ui.views.ItemTypes.get_latest',
            return_value=[orphan_item_type_name, valid_item_type_name]
        ):
            response = get_itemtypes()

    assert response.get_json() == [{
        'id': 2,
        'name': 'valid',
        'tag': 1,
        'harvesting_type': False,
        'is_deleted': False
    }]

    
    
