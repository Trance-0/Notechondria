
import os
import pandas as pd
import random
import csv
from openai import OpenAI
from dotenv import load_dotenv, find_dotenv
from django.core.files.storage import default_storage
from .models import WordDict




def __openAI_promt_message(k,v):
    client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))
    completion = client.chat.completions.create(
    model='gpt-4',
    messages=[
        {'role': 'system', 'content': os.environ.get('SYSTEM_PROMPT')},
        {'role': 'user', 'content': f'Compose a paragraph to help me remember the key value pair {k}, {v}'}
    ]
    )
    print(completion.choices[0].message.content)
    
    
    
def __cols_selection_validation(vals,input_str):
    # validation value_names
    cur_cols=input_str.split(',')
    for i in cur_cols:
        if i not in vals:
            return []
    return cur_cols


def process_csv(file_path ,memcsv_instance):
    file = default_storage.open(file_path, mode='r', encoding='utf-8')
    reader = csv.reader(file, delimiter=';')

    
    
    for row in reader:
        japanese, english = row

        # Create WordDict entry with the relationship to memcsv_instance
        WordDict.objects.create(
            japanese=japanese,
            english=english,
            memcsv=memcsv_instance  # Ensure this field matches the ForeignKey field in your model
            )
    
    file.close()