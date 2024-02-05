# pull official base image
FROM python:3.9-bullseye as builder

WORKDIR /usr/src/app 
COPY requirements.txt .
RUN pip3 install -r requirements.txt --no-cache-dir
COPY . . 

ADD ./entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh 

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]