FROM ruby:2.6-slim
RUN apt-get update \
    && apt-get install -y git openssh-client \
    && rm -rf /var/lib/apt/lists/*
RUN git clone https://github.com/cjmateos/croqueta.git /opt/croqueta
RUN gem install aws-sdk-ec2 && gem install aws-sdk-s3 && gem install sshkey && gem install colorize
RUN mkdir -p /opt/croqueta/conf && mkdir -p /opt/croqueta/keys && mkdir -p /root/.aws
RUN useradd -r -u 1001 -g root -m -d /home/nonroot nonroot
RUN chmod -R g+rwX /opt/croqueta
VOLUME /opt/croqueta/conf
VOLUME /opt/croqueta/keys
VOLUME /home/nonroot/.aws
USER 1001
WORKDIR /opt/croqueta
CMD ["ruby", "croqueta.rb"]
