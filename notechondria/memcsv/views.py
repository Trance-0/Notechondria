from django.shortcuts import get_object_or_404, render
from django.shortcuts import redirect, render
from django.contrib import messages
from django.contrib.auth.decorators import login_required
from django.contrib.auth.models import User
from creators.models import Creator

from .models import MemCSV,MemRecord
# Create your views here.

@login_required
def memlist(request):
    user_instance = request.user
    creator_instance = get_object_or_404(Creator, user_id=user_instance)
    # get list of csvs
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

# def recordCreate(request,csc_pk):

# def memtest(request,rec_pk):
#     if request.method=="POST":
#         answer=