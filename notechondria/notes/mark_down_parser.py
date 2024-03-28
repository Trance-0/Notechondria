""" a module responsible for converting markdown file to a new note.

"""

import regex as re
from .models import Note, NoteBlock, NoteIndex, NoteBlockTypeChoices
from creators.models import Creator

class BlockGenerator:
    """custom generator for each block type 
    """
    
    # rules for rendering single line blocks
    __single_line_blocks = [
        NoteBlockTypeChoices.TITLE,
        NoteBlockTypeChoices.URL,
        NoteBlockTypeChoices.SUBTITLE,
        NoteBlockTypeChoices.IMAGES,
    ]

    # house rule for markdown regex matching, the order matters
    __md_rules = {
        NoteBlockTypeChoices.CODE:("^`{3}","^`{3}"),
        NoteBlockTypeChoices.EXAMPLE: ("^Example:\s*",""),
        NoteBlockTypeChoices.PROOF: ("(^Proof:\s*)",""),
        NoteBlockTypeChoices.TITLE: "(^#{1}\h)(?<text>.*)",
        NoteBlockTypeChoices.URL: "^\[(?<text>.*)\]\((?<args>(http)(?:s)?(\:\/\/).*)\)",
        NoteBlockTypeChoices.SUBTITLE: "(?<args>^#{2,4})\h(?<text>.*)",
        NoteBlockTypeChoices.IMAGES: ("^!\[(?<text>.*)\]\((?<images>.*)\)"),
        NoteBlockTypeChoices.QUOTE: ("(^>\h+)(.*\s{2})"),
        NoteBlockTypeChoices.LIST: (""),
    }


    def __init__ (self,block_type:NoteBlockTypeChoices):
        if block_type not in self.__md_rules.keys():
            raise Exception(f"Unsupported block type: {block_type}")
        if block_type in self.__single_line_blocks:
            self.head=self.__md_rules[block_type]
        else:
            self.head, self.end=self.__md_rules[block_type]
        self.block_type=block_type
    
    def __arg_required(self):
        arg_required_choices=[NoteBlockTypeChoices.CODE,
                              NoteBlockTypeChoices.URL,
                              NoteBlockTypeChoices.SUBTITLE,
                              Note]
        return self.block_type in arg_required_choices
    
    def isBlock(self,md_str):
        return re.match(md_str,self.head)!=None

    def load_content(self,md_str:list[str]):
        return False

    def load_block(self,creator:Creator, note:Note=None):
        if self.text==None:
            raise Exception('Please call load content before load block!')
        # create new block instance only (we have no way to track old blocks), delete original blocks before load
        block_instance=NoteBlock.objects.create(creator_id=creator,
                                                note_id=note,
                                                block_type=self.block_type,
                                                text=self.text)




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
