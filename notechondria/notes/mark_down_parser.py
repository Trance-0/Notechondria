""" a module responsible for converting markdown file to a new note.

"""
import re
from .models import Note,NoteBlock,NoteIndex,NoteBlockTypeChoices
import markdown as md
from markdown.blockprocessors import BlockProcessor
from markdown import Extension
import xml.etree.ElementTree as etree

# load custom extension
# reference: https://github.com/Python-Markdown/markdown/blob/master/docs/extensions/api.md
class ProofBlockProcessor(BlockProcessor):
    RE_FENCE_START = r'^Proof: *\n' # start line
    RE_FENCE_END = r'\n\s*$'  # last non-blank line

    def test(self, parent, block):
        return re.match(self.RE_FENCE_START, block)

    def run(self, parent, blocks):
        original_block = blocks[0]
        blocks[0] = re.sub(self.RE_FENCE_START, '', blocks[0])

        # Find block with ending fence
        for block_num, block in enumerate(blocks):
            if re.search(self.RE_FENCE_END, block):
                # remove fence
                blocks[block_num] = re.sub(self.RE_FENCE_END, '', block)
                # render fenced area inside a new div
                e = etree.SubElement(parent, 'div')
                e.set('class', 'p-3 mb-2 bg-body-secondary')
                self.parser.parseBlocks(e, blocks[0:block_num + 1])
                # remove used blocks
                for i in range(0, block_num + 1):
                    blocks.pop(0)
                return True  # or could have had no return statement
        # No closing marker!  Restore and do nothing
        blocks[0] = original_block
        return False  # equivalent to our test() routine returning False

class ProofExtension(Extension):
    def extendMarkdown(self, md):
        md.parser.blockprocessors.register(ProofBlockProcessor(md.parser), 'box', 175)

def md_to_note(note:Note,md_str:str):
    html=md.markdown(md_str)
    print(html)
    # convert based on html

def md_to_html(md_str:str):
    return md.markdown(md_str)

def note_to_html(note:Note):
    note_indexes= NoteIndex.objects.filter(note_id=note).order_by("index")
    return md.markdown("\n\n".join([i.noteblock_id.get_md_str() for i in note_indexes]))