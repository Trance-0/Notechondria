# pull official base image
FROM python:3.9-bullseye as builder
EXPOSE 8000
WORKDIR /usr/src/app 
COPY requirements.txt .
RUN pip3 install -r requirements.txt --no-cache-dir
COPY . . 
ENTRYPOINT ["./entrypoint.sh"]
