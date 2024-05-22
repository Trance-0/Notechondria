import pandas as pd
import random

# global variables

debug=True

# threshold for mapping as 'knowing'
bayes_threshold=0.8

epoch=10

# local variables

card_file_name='N/A'
df=pd.DataFrame(data={})
key_cols=[]
training_type_dict={'S':'normal traininig with selection value',
                    'I':'normal training with direct text input'}
training_type='S'
val_cols=[]

     
def __cols_selection_validation(vals,str):
    # validation value_names
    cur_cols=str.split(',')
    for i in cur_cols:
        if i not in vals:
            return []
    return cur_cols
    
def input_training(row_replacement=False):
    ''' return by input
    '''
    
    global df
    
    for i in range(epoch):
        # select cols
        cur_key_name,cur_val_name=df.columns.values[0],df.columns.values[1]
        
        # shuffle
        df=df.sample(frac=1)
        
        # select rows
        if row_replacement:
            question_df=df.sample(n=1)
        else:
            question_df=df.iloc[[(i%len(df.index))+1]]
        if len(key_cols)==0:
            cur_key_name=random.choice(df.columns.values)
        else:
            cur_key_name=random.choice(key_cols)
        if len(val_cols)==0:
            cur_val_name=random.choice(df.columns.values)
            while cur_val_name==cur_key_name:
                cur_val_name=random.choice(df.columns.values)
        else:
            cur_val_name=random.choice(val_cols)
        ans=input(f' return the {cur_val_name} of {question_df[cur_key_name].to_string(index=False)} \n')
        print('correct answer: ',question_df[cur_val_name].to_string(index=False))

def selection_training(options=5,random_row=True):
    ''' Not fully implemented yet
    '''
    raise Exception('function not implemented yet')
    for i in range(epoch):
        # select rows
        cur_key_name,cur_val_name=df.columns.values[0],df.columns.values[1]
        if random_row:
            question_df=df.sample(n=options)
        else:
            question_df=df.sample(n=options-1)
            # question_df.loc[options]=df[]
        if len(key_cols)==0:
            cur_key_name=random.choice(df.columns.values)
        else:
            cur_key_name=random.choice(key_cols)
        if len(val_cols)==0:
            cur_val_name=random.choice(df.columns.values)
            while len(key_cols)==0 and cur_val_name==cur_key_name:
                cur_val_name=random.choice(df.columns.values)
        else:
            cur_val_name=random.choice(val_cols)

card_file_name=input('Please enter your file name: (or command to make your life easier, start with character --cmd or --help for extra guiding) ')

df=pd.read_csv(f'./{card_file_name}.csv',sep=';')

epoch=len(df.index)

if debug:
    print(df.head())

# Select training mode
print('init sucess, please select training mode from the list below')
# print prompt
for key,val in training_type_dict.items():
    print(f'[{key}] --{val}')
training_type=input()
while training_type not in training_type_dict.keys():
    training_type=input('traing type not found, please select from the type list with sigle capital letter like S')
    
cols=df.columns.values.tolist()

if len(cols)<2:
    raise Exception('invaid csv, the col number should be at least 2.')

# select key vals
print('Please enter the column name for key, separated by ",", leave it blank is you want to test everything, detected selection are below: ')
key_name=input(cols)
parse_values=__cols_selection_validation(cols,key_name)
while len(key_name)!=0 and len(parse_values)==0:
    key_name=input(f'key name {key_name} not found, please select from below '+f.columns.values+'\n')
    parse_values=__cols_selection_validation(cols,key_name)
key_cols=parse_values  

for i in key_cols:
    cols.remove(i)

# select testing values
print('Please select testing value below, separated by ",", leave it blank is you want to test everything')
value_name=input(cols)
parse_values=__cols_selection_validation(cols,value_name)
while len(value_name)!=0 and len(parse_values)==0:
    value_names=input('invalid value names, please select testing value below,separated by ',' leave it blank is you want to test everything')
    parse_values=__cols_selection_validation(testing_cols,value_names)
val_cols=parse_values

if training_type=='S':
    selection_training()
elif training_type=='I':
    input_training()
    
   
    
    
