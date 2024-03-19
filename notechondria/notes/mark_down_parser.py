""" a module responsible for converting markdown file to a new note.

"""
import re
from .models import Note,NoteBlock,NoteIndex,NoteBlockTypeChoices

# house rule for markdown regex matching, the order matters
md_rules=[
    (NoteBlockTypeChoices.CODE,"(^\`{3}.*\s)((.*\s)*)(^\`{3}\s{2})"),
    (NoteBlockTypeChoices.TITLE,"(^#{1}\h)(.*\s{2})"),
    (NoteBlockTypeChoices.URL,"(^\[.*\])(\((http)(?:s)?(\:\/\/).*\)\s{2})"),
    (NoteBlockTypeChoices.SUBTITLE,"(^#{2,4}\h)(.*\s{2})"),
    (NoteBlockTypeChoices.EXAMPLE,"(^Example:\s*)(.*\s{2})"),
    (NoteBlockTypeChoices.PROOF,"(^Proof:\s*)(.*\s{2})"),

    (NoteBlockTypeChoices.QUOTE,"(^>\h+)(.*\s{2})"),
    (NoteBlockTypeChoices.IMAGES,"(^!\[.*\])(.*\s{2})"),
    (NoteBlockTypeChoices.LIST,"")
]

def md_to_note(note:Note,md_str:str):
    """function that use regex to parse md_str to notes

    use my own typing style. lol.

    Attributes:
        note: Note object to write on, not responsible for deletion, just return note object and create noteblock based on that.
        md_str: markdown string with my style.
    """
    html=""
    print(html)
    # convert based on html

def md_to_html(md_str:str):
    return ""

def note_to_md(note:Note):
    note_indexes= NoteIndex.objects.filter(note_id=note).order_by("index")
    return "\n\n".join([i.noteblock_id.get_md_str() for i in note_indexes])