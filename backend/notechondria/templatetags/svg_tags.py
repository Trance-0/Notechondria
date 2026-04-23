"""
referenced tutorial: 
https://stackoverflow.com/questions/25954797/how-to-embed-an-svg-image-in-a-django-template
"""

from pathlib import Path
import os
import xml.etree.ElementTree as ET

from django import template
from django.utils.safestring import mark_safe

register = template.Library()

BASE_DIR = Path(__file__).resolve().parent.parent.parent

ICON_DIR = os.path.join(BASE_DIR,'media','bs_icon')

@register.simple_tag
def svg_tags(file_name, class_str=None, size=24, fill='#000000'):
    """Inlines a SVG icon from icon dir
    Example usage:
        {% icon 'face' 'std-icon menu-icon' 32 '#ff0000' %}
    Parameter: file_name
        Name of the icon file excluded the .svg extention.
    Parameter: class_str
        Adds these class names, use "foo bar" to add multiple class names.
    Parameter: size
        An integer value that is applied in pixels as the width and height to
        the root element.
        The material.io icons are by default 24px x 24px.
    Parameter: fill
        Sets the fill color of the root element.
    Returns:
        XML to be inlined, i.e.:
        <svg width="..." height="..." fill="...">...</svg>
    """
    path = os.path.join(ICON_DIR,f'{file_name}.svg')
    if not Path(path).is_file():
        path = os.path.join(ICON_DIR,f'bug.svg')
    ET.register_namespace('', "http://www.w3.org/2000/svg")
    tree = ET.parse(path)
    root = tree.getroot()
    root.set('class', class_str)
    root.set('width', f'{size}px')
    root.set('height', f'{size}px')
    root.set('fill', fill)
    svg = ET.tostring(root, encoding="unicode", method="html")
    return mark_safe(svg)