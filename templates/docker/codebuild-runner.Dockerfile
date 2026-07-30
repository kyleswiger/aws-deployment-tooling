# Custom CodeBuild runner: Amazon Linux 2 standard 5.0 + Terraform + baked deps.
#
# Rebuild this image (via the dedicated runner-image CodeBuild project +
# buildspec-codebuild-image.yml) when upgrading Terraform or your Lambda deps —
# NOT on every app build. Baking wheels/toolchains here keeps routine app
# pipelines fast (they skip most `pip install` / tool download time).
#
# The base image matches the tooling expectations of aws/codebuild/standard:5.0
# (Python 3.9, Node 18, Docker-in-Docker). Bump the base tag for newer runtimes.
FROM public.ecr.aws/codebuild/amazonlinux2-x86_64-standard:5.0

USER root

ARG TERRAFORM_VERSION=1.9.8
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
      -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin \
    && rm /tmp/terraform.zip \
    && chmod +x /usr/local/bin/terraform \
    && terraform version

# Bake your Lambda/build Python wheels so app pipelines spend less time in pip.
# Adjust the COPY paths to your repo's requirements files (or remove if unused).
WORKDIR /tmp/bake
COPY src/api/requirements.txt /tmp/bake/api-requirements.txt
RUN pip3 install -r /tmp/bake/api-requirements.txt \
    && rm -rf /tmp/bake

WORKDIR /root
