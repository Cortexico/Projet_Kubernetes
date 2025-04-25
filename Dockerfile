FROM nginx:latest
USER root
RUN apt-get update && apt-get install -y stress-ng && rm -rf /var/lib/apt/lists/*