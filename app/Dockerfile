FROM ubuntu:25.04

RUN apt update && apt install -y suricata ruby rubygems bundler

RUN mkdir /app
COPY . /app/

RUN chown -R root:root /app
WORKDIR /app
EXPOSE 1234

RUN bundle install

# Run as the CTF user
RUN useradd -r user -u 1100
USER 1100

ENV DEBUG=true
ENV PROFILE=prod

CMD ["bundle", "exec", "ruby", "/app/server.rb"]
