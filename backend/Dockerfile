# pull official base image
FROM python:3.9.18-bullseye AS builder

# configurations
ENV HOME=/home
ENV APP_HOME=/home/notechondria
ENV PRODUCTION_MEDIA_ROOT=/home/mediafiles
ENV PRODUCTION_STATIC_ROOT=/home/staticfiles
RUN mkdir ${APP_HOME}

RUN apt-get update \
    && apt-get install -y --no-install-recommends netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# install dependencies
WORKDIR $HOME 
RUN pip install --upgrade pip
COPY requirements.txt .
RUN pip3 install -r requirements.txt --no-cache-dir

# copy files
WORKDIR ${APP_HOME}
COPY . . 

# add entrypoint to root
ADD ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh 

# create the appropriate directories for static and media file (nginx)
# nginx only process medias and should not be exposed.
RUN mkdir $HOME/staticfiles
RUN mkdir $HOME/mediafiles

# make log directory
RUN mkdir ${APP_HOME}/log

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
