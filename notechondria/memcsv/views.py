

import os
import pandas as pd
import random
from openai import OpenAI
from dotenv import load_dotenv, find_dotenv
from .models import  WordDict
from .utils import process_csv


# Django import
from django.shortcuts import get_object_or_404, render
from django.shortcuts import redirect, render
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.views.decorators.http import require_POST
from django.contrib.auth.models import User
from creators.models import Creator
from .forms import  MemCSVForm
from .models import MemCSV, MemRecord
from .utils import __openAI_promt_message, __cols_selection_validation
from django.http import HttpResponse
# Create your views here.

@login_required
def memlist(request): 
    user_instance = request.user
    creator_instance = get_object_or_404(Creator, user_id=user_instance)
    # get list of csv
    csv_list=MemCSV.objects.filter(creator_id=creator_instance)
    if request.method=="POST":
        csv_pk=request.POST.get('mem_id', -1)
        # return when post don't have desired param
        if csv_pk==-1:
            messages.error(request,f"requested csv file not found")
            return render(request,"memcsv.html",context={"csv_list":csv_list})
        # return when parameter invalid
        _=get_object_or_404(MemCSV, csv_pk=csv_pk)
        return redirect("memcsv:test",pk=csv_pk)
    return render(request,"memcsv.html",context={"csv_list":csv_list})







# Django tips for document uploads: https://docs.djangoproject.com/en/5.0/topics/http/file-uploads/



# Post/redirect/View

# @login_required
# @require_POST
def upload_memcsv(request):
    
    # I am assuming here we only handle a request getting a file
    if request.method == 'POST':
        form = MemCSVForm(request.POST, request.FILES)    # Create and instance of the MemCSVForm  # Why can you pass in request.Post Dictionary like structure
        if form.is_valid():   #if the file form is valid I add in all the other data of the request_user to the MemCSV Model since it is conbination of User + File 
            
            
            # I mannual set these variables because I feel that giving the user the ability to fill in what they claim their id is doesn't seem like a good securitiy approach.
            
            memcsv_instance = form.save(commit=False) 
            # Creates a model instance. 
            # For ModelForms save usually creates a model instance with the data bounded to the form and then save it to the data base. 
            # Here it creates the instance without saving it to the database
                
            memcsv_instance.creator_id = request.user.creator_id 
            # marked the instance of file upload with its user
            # If we dont use form.save(commit=False) we can also use "form.instance.creator_id = request.user"
            # the instance attribute holds a reference to the model instance that the form is either representing or will be representing so you can also use
            
            memcsv_instance.sharing_id = request.user.sharing_id 
       
            # This will automatically be saved to the model since I created the form according to the model as a modelfrom
            
            memcsv_instance.save(commit=True)  
            # Access the file through the instance csv_file feild since each instance can only have one file as defined in the model
            file_path = memcsv_instance.csv_file.path  
            
            try:
            
                process_csv(file_path, memcsv_instance) #dictionary
                # if request.user.is_authenticated:
                   
       
                
                                   
                # Convert DataFrame to dictionary for session storage since I don't think it directly support storing complex objects like pandas DataFrames due to some serialization requirements
                # When does a session end?
                
                # FYI double check Edit the MIDDLEWARE setting and make sure it contains 'django.contrib.sessions.middleware.SessionMiddleware'. 
                # The default settings.py created by django-admin startproject has SessionMiddleware activated.(I haven't checked yet)
                # https://docs.djangoproject.com/en/5.0/topics/http/sessions/
                
                return  HttpResponse("Sucess?") #change 
            
            #I am directing it to input_training for now since it is the only implemented one
                # later I will redirect to a selelction form to redirect to other two urls for input and selection training. Or I can simply have multiple
                # Or redirect to the view Training_ModeSelection(request)
                # views in one url? I don't know how to handle that
            
            except Exception as e:
                messages.error(request, f'Error processing the file: {e}')
        
        else:
            # Add an error message if the form is not valid
            # It does not directly return the message but makes it available for display in the template rendered for the user.
            messages.error(request, "There was an error processing your form. Please check your input and try again.")
   
    else:
         form = MemCSVForm() # No changes to data base

    return render(request, 'upload_memcsv.html', context={'form': form})  # This wiil re-render the upload page since user failed and they can attempt to upload again




""" 

#select file deful
    
# @login_required
#@require_POST
def input_training(request):
    # Is this request POST?
    # Load the DataFrame from the session or redirect if not available
    
    if request.method == 'POST':
    
        if 'df' not in request.session:   # this should no longer be session but instead be asking if the previous stored model is empty?
            messages.error(request, "No data available. Please upload your CSV file first.")
            return redirect('upload_memcsv')
        
        
        # these are the variables that are actually used for the training I am not exactly sure how the POST form will be set up and what variables will pass in
        # I assume we don't need a model to store these varaiible since they are specific to the session of training?
        
    
        #.get allows you to provide an additional parameter of a default value which is returned if the key is not in the dictionary.
        # For example, request.POST.get('sth', 'mydefaultvalue')
        
        
        # here we should have a form that allows the user to select which dictionary they want to use for training/ what does it mean to select multiple ones?
        
        df = pd.DataFrame(request.session['df'])   #global? hence get rid of the session 
        
        
        df = df.sample(frac=1)  # Shuffle the DataFrame 
        
        
        # form =  TrainingForm()
        # ..... some form I need to implement, these are the varibles that could be asked in another view I think. Such as the picking what type of training view 
        # I think here the form should be dedicated to asking questions and getting answers
        #if we did make a form this would be assigning the variable using the non-raw data. Feels more 
        
        
        #inform
        if not form.is_valid(): 
            messages.error(request, "Data not clean")
            return redirect('upload_memcsv')
        
        # Hidden feild, ajx     , update templte
        epoch = form.cleaned_data.get('epoch', 3)
        row_replacement = form.cleaned_data.get('row_replacement', False)
        key_cols = form.cleaned_data.get('key_cols', [])
        training_type = form.cleaned_data.get('training_type', 'S')
        val_cols = form.cleaned_data.get('val_cols', [])
        
        
        row_replacement = request.POST.get('row_replacement')
        
        if row_replacement is None:
            row_replacement = False

         
         
         
        # get rid of this loop somehow and make sure that it
         
        for i in range(epoch):
            # select cols
            cur_key_name,cur_val_name=df.columns.values[0],df.columns.values[1]       
            
            # select rows
            if row_replacement:
                question_df=df.sample(n=1)
            else:
                question_df=df.iloc[[i%len(df.index)]]
                
            # Determine key and value names

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
            
            # Process user input
                        
                      
            messages.info(f'Type the {cur_val_name} of [{question_df[cur_key_name].to_string(index=False)}] \n') # These messages don't give real time response
            ans = form.cleaned_data.get('answer')  # ..... some form I need to implement a form that contiously gets different anwser 
            messages.info('correct answer: ',question_df[cur_val_name].to_string(index=False))
            
            
 
    
            correct_answer = question_df[cur_val_name].to_string(index=False)
            question = f'Type the {cur_val_name} of [{question_df[cur_key_name].to_string(index=False)}]\n'
    
            # Yield the response data ??????
            yield {
                    'answer': ans,
                    'correct_answer': correct_answer,
                }
    

            
            if not ans==question_df[cur_val_name].to_string(index=False):
                need_help=input(f'is your answer correct? type anything to get help from GPT teacher.')
                if len(need_help)>0:
                    help_count+=1
                    
                    
                    messages.info(request,'loading response from openAI, this might take a while...')
                    __openAI_promt_message(question_df[cur_key_name].to_string(index=False),
                                        question_df[cur_val_name].to_string(index=False))
                    
        loss="{:.2f}".format(help_count/epoch)
        messages.success(request, f'Training ends, total epoch: {epoch}, errors: {help_count}, loss: {loss}')



    
# @login_required
def Training_ModeSelection(request):
    
    
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
        key_name=input(f'key name {key_name} not found, please select from below '+df.columns.values+'\n')
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
        parse_values=__cols_selection_validation(cols,value_names)
    val_cols=parse_values

    if training_type=='S':
        selection_training()
    elif training_type=='I':
        input_training()



# def Training_ModeSelection(request): we need a seperate view that handles how files are downloaded which is also with validation of user subscription and wether they
#allow their file to be download or not
# you do not need to be subscribeed in order to download but the other user must allow you to use their file

"""