""" a module responsible for converting markdown file to a new note.

"""
from .models import Note,NoteBlock,NoteIndex

def md_to_note(note:Note,md_str:str):
    # clear up note and related indices
    noteIndex=NoteIndex.objects.filter(note_id=note)
    for idx in noteIndex:
        # we do not delete idx.noteblock because they are probably reference
        idx.delete()
    # clear up noteblock
    noteBlocks=NoteBlock.objects.filter(note_id=note)

def md_to_html(md_str:str,note:Note=None):
    return ""