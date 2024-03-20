""" custom backslash replace filter

"""
from django import template

register = template.Library()

safe_txt_rules={
    "&":"&amp;",
    "\\":"&bs;",
    "`" :"&bt;",
    "'":"&#x27;",
    '"' : "&quot;",
    "<": "&lt;",
    ">": "&gt;",
}

@register.filter(name="md_str_esc")
def md_str_esc(value):
    """ custom function for markdown safe string

    There are many other rules but I will focus on the most important 7s.

    Attributes:
        value: raw md string in python
    Returns:
        safe string using custom conversion rule below:

        "&" -> "&amp;"
        "\" -> "&bs;"
        "`" -> "&bt;"
        "'" -> "&#x27;"
        '"' -> "&quot;"
        "<" -> "&lt;"
        ">" -> "&gt;"

    """
    for k,v in safe_txt_rules.items():
        value=value.replace(k,v)
    return value