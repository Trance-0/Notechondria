""" a module responsible for converting markdown file to a new note.

"""

import regex as re
from .models import Note, NoteBlock, NoteIndex, NoteBlockTypeChoices

# house rule for markdown regex matching, the order matters
md_rules = [
    (NoteBlockTypeChoices.CODE, "(^\`{3}.*\s)((.*\s)*)(^\`{3}\s{2})"),
    (NoteBlockTypeChoices.TITLE, "(^#{1}\h)(.*\s{2})"),
    (NoteBlockTypeChoices.URL, "(^\[.*\])(\((http)(?:s)?(\:\/\/).*\)\s{2})"),
    (NoteBlockTypeChoices.SUBTITLE, "(^#{2,4}\h)(.*\s{2})"),
    (NoteBlockTypeChoices.EXAMPLE, "(^Example:\s*)(.*\s{2})"),
    (NoteBlockTypeChoices.PROOF, "(^Proof:\s*)(.*\s{2})"),
    (NoteBlockTypeChoices.QUOTE, "(^>\h+)(.*\s{2})"),
    (NoteBlockTypeChoices.IMAGES, "(^!\[.*\])(.*\s{2})"),
    (NoteBlockTypeChoices.LIST, ""),
]

# rules for rendering single line blocks
single_line_blocks = [
    NoteBlockTypeChoices.TITLE,
    NoteBlockTypeChoices.URL,
    NoteBlockTypeChoices.SUBTITLE,
    NoteBlockTypeChoices.IMAGES,
]

def clean_block_string(md_str: str, block_type: NoteBlockTypeChoices):
    # single line blocks
    if block_type in single_line_blocks:
        return re.sub(r"([\r\n]+)", r" ", md_str)
    else:
        return re.sub(r"([\r\n]{2,})", r"\n", md_str)


def md_to_note(note: Note, md_str: str):
    """function that use regex to parse md_str to notes

    use my own typing style. lol.

    Attributes:
        note: Note object to write on, not responsible for deletion, just return note object and create noteblock based on that.
        md_str: markdown string with my style.
    """
    html = ""
    print(html)
    # convert based on html


def md_to_html(md_str: str):
    return ""


def note_to_md(note: Note):
    note_indexes = NoteIndex.objects.filter(note_id=note).order_by("index")
    return "\n\n".join([i.noteblock_id.get_md_str() for i in note_indexes])
