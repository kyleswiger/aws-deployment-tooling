# syntax=docker/dockerfile:1.7
# Container-image Lambda for a Python service. Pairs with the lambda-container
# Terraform module.
#
# Base image is pinned by digest so rebuilds are reproducible and a surprise
# upstream push can't silently change the runtime. Refresh the digest
# deliberately (pull the tag, record the new sha256) when you want base updates.
#
# Adjust src/api paths to your repo layout. `src/shared` holds code shared across
# multiple Lambdas; drop that COPY if you don't have one.
# ADAPT: Replace this placeholder digest with a real sha256 for public.ecr.aws/lambda/python:3.12
ARG LAMBDA_PY_DIGEST=<PLACEHOLDER_DIGEST>
FROM public.ecr.aws/lambda/python:3.12@${LAMBDA_PY_DIGEST}

COPY src/api/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir -r requirements.txt \
 && rm -rf /root/.cache

COPY src/shared/ ./shared/
COPY src/api/ .

# "<module>.<function>" — the handler entrypoint (e.g. main.handler).
CMD [ "main.handler" ]
