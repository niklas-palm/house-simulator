.PHONY: help install check-deps check-ecs-role build-camera-simulator build-telemetry-simulator build-weather-service build-heater-service push-camera-simulator push-telemetry-simulator push-weather-service push-heater-service deploy outputs delete all

# Variables
AWS_REGION ?= eu-west-1
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query Account --output text)
CAMERA_REPO_NAME := camera-simulator
TELEMETRY_REPO_NAME := telemetry-simulator
WEATHER_REPO_NAME := weather-service
HEATER_REPO_NAME := heater-service
CAMERA_IMAGE_URI := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(CAMERA_REPO_NAME):latest
TELEMETRY_IMAGE_URI := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(TELEMETRY_REPO_NAME):latest
WEATHER_IMAGE_URI := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(WEATHER_REPO_NAME):latest
HEATER_IMAGE_URI := $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(HEATER_REPO_NAME):latest
STACK_NAME := house-simulator
VIDEO_URL := https://d3aubck6is8zpr.cloudfront.net/agentbootcampvideo2.mp4

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RESET := \033[0m

help:
	@echo "$(CYAN)Data Simulator System - Makefile Commands$(RESET)"
	@echo ""
	@echo "$(GREEN)Setup Commands:$(RESET)"
	@echo "  make install                     - Install dependencies (Docker, AWS CLI, etc.)"
	@echo "  make check-deps                  - Check if all dependencies are installed"
	@echo "  make check-ecs-role              - Ensure ECS service-linked role exists (run once per account)"
	@echo ""
	@echo "$(GREEN)Build Commands:$(RESET)"
	@echo "  make build-camera-simulator      - Build camera simulator Docker image"
	@echo "  make build-telemetry-simulator   - Build telemetry simulator Docker image"
	@echo "  make build-weather-service       - Build weather service Docker image"
	@echo "  make build-heater-service        - Build heater MCP service Docker image"
	@echo ""
	@echo "$(GREEN)Push Commands:$(RESET)"
	@echo "  make push-camera-simulator       - Push camera image to ECR (creates repo if needed)"
	@echo "  make push-telemetry-simulator    - Push telemetry image to ECR (creates repo if needed)"
	@echo "  make push-weather-service        - Push weather service image to ECR (creates repo if needed)"
	@echo "  make push-heater-service         - Push heater service image to ECR (creates repo if needed)"
	@echo ""
	@echo "$(GREEN)Deploy Commands:$(RESET)"
	@echo "  make deploy                      - Deploy CloudFormation stack"
	@echo "  make outputs                     - Show CloudFormation stack outputs"
	@echo ""
	@echo "$(GREEN)Cleanup Commands:$(RESET)"
	@echo "  make delete                      - Delete all resources (S3, ECR, CloudFormation stack)"
	@echo ""
	@echo "$(GREEN)Combined Commands:$(RESET)"
	@echo "  make all                         - Build, push, and deploy everything"
	@echo ""
	@echo "$(YELLOW)Variables:$(RESET)"
	@echo "  AWS_REGION=$(AWS_REGION)"
	@echo "  AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID)"
	@echo "  STACK_NAME=$(STACK_NAME)"

install:
	@echo "$(CYAN)Installing dependencies...$(RESET)"
	@echo "$(YELLOW)Detecting operating system...$(RESET)"
	@if [ -f /etc/os-release ]; then \
		. /etc/os-release; \
		if [ "$$ID" = "amzn" ]; then \
			echo "$(GREEN)Detected Amazon Linux$(RESET)"; \
			echo "$(YELLOW)Installing Docker...$(RESET)"; \
			sudo yum update -y; \
			sudo yum install -y docker git; \
			sudo systemctl enable docker; \
			sudo systemctl start docker; \
			sudo usermod -aG docker $$USER; \
		elif [ "$$ID" = "ubuntu" ]; then \
			echo "$(GREEN)Detected Ubuntu$(RESET)"; \
			echo "$(YELLOW)Installing Docker...$(RESET)"; \
			sudo apt-get update -y; \
			sudo apt-get install -y docker.io git; \
			sudo systemctl enable docker; \
			sudo systemctl start docker; \
			sudo usermod -aG docker $$USER; \
		else \
			echo "$(YELLOW)Unsupported OS: $$ID$(RESET)"; \
			exit 1; \
		fi; \
	else \
		echo "$(YELLOW)Cannot detect OS. Please install Docker and AWS SAM CLI manually.$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Installation complete!$(RESET)"
	@echo "$(YELLOW)IMPORTANT: You may need to log out and log back in for Docker permissions to take effect.$(RESET)"
	@echo "$(YELLOW)Or run: newgrp docker$(RESET)"

check-deps:
	@echo "$(CYAN)Checking dependencies...$(RESET)"
	@which docker > /dev/null || (echo "$(YELLOW)Docker not found. Run 'make install'$(RESET)" && exit 1)
	@which aws > /dev/null || (echo "$(YELLOW)AWS CLI not found. Please install AWS CLI.$(RESET)" && exit 1)
	@docker ps > /dev/null 2>&1 || (echo "$(YELLOW)Docker daemon not running or permission denied. Try 'newgrp docker' or restart.$(RESET)" && exit 1)
	@echo "$(GREEN)All dependencies are installed!$(RESET)"

check-ecs-role:
	@echo "$(CYAN)Checking ECS service-linked role...$(RESET)"
	@aws iam get-role --role-name AWSServiceRoleForECS > /dev/null 2>&1 && \
		echo "$(GREEN)ECS service-linked role exists$(RESET)" || \
		(echo "$(YELLOW)Creating ECS service-linked role...$(RESET)" && \
		aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com && \
		echo "$(GREEN)ECS service-linked role created$(RESET)")

build-camera-simulator:
	@echo "$(GREEN)Building camera simulator image...$(RESET)"
	docker build --platform linux/arm64 --build-arg VIDEO_URL=$(VIDEO_URL) -t $(CAMERA_REPO_NAME):latest ./camera-simulator
	@echo "$(GREEN)Camera simulator image built successfully$(RESET)"

build-telemetry-simulator:
	@echo "$(GREEN)Building telemetry simulator image...$(RESET)"
	docker build --platform linux/arm64 -t $(TELEMETRY_REPO_NAME):latest ./temperature-simulator
	@echo "$(GREEN)Telemetry simulator image built successfully$(RESET)"

build-weather-service:
	@echo "$(GREEN)Building weather service image...$(RESET)"
	docker build --platform linux/amd64 -t $(WEATHER_REPO_NAME):latest ./weather-service
	@echo "$(GREEN)Weather service image built successfully$(RESET)"

build-heater-service:
	@echo "$(GREEN)Building heater MCP service image...$(RESET)"
	docker build --platform linux/amd64 -t $(HEATER_REPO_NAME):latest ./heater-service
	@echo "$(GREEN)Heater MCP service image built successfully$(RESET)"

push-camera-simulator: build-camera-simulator
	@echo "$(GREEN)Logging into ECR...$(RESET)"
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	@echo "$(GREEN)Checking if ECR repository exists...$(RESET)"
	@aws ecr describe-repositories --repository-names $(CAMERA_REPO_NAME) --region $(AWS_REGION) 2>/dev/null || \
		(echo "$(YELLOW)Creating ECR repository $(CAMERA_REPO_NAME)...$(RESET)" && \
		aws ecr create-repository --repository-name $(CAMERA_REPO_NAME) --region $(AWS_REGION))
	@echo "$(GREEN)Tagging and pushing camera image...$(RESET)"
	docker tag $(CAMERA_REPO_NAME):latest $(CAMERA_IMAGE_URI)
	@for i in 1 2 3; do \
		echo "$(YELLOW)Push attempt $$i of 3...$(RESET)"; \
		if docker push $(CAMERA_IMAGE_URI); then \
			echo "$(GREEN)Camera image pushed successfully$(RESET)"; \
			break; \
		else \
			if [ $$i -lt 3 ]; then \
				echo "$(YELLOW)Push failed, retrying in 5 seconds...$(RESET)"; \
				sleep 5; \
			else \
				echo "$(YELLOW)Push failed after 3 attempts$(RESET)"; \
				exit 1; \
			fi; \
		fi; \
	done

push-telemetry-simulator: build-telemetry-simulator
	@echo "$(GREEN)Logging into ECR...$(RESET)"
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	@echo "$(GREEN)Checking if ECR repository exists...$(RESET)"
	@aws ecr describe-repositories --repository-names $(TELEMETRY_REPO_NAME) --region $(AWS_REGION) 2>/dev/null || \
		(echo "$(YELLOW)Creating ECR repository $(TELEMETRY_REPO_NAME)...$(RESET)" && \
		aws ecr create-repository --repository-name $(TELEMETRY_REPO_NAME) --region $(AWS_REGION))
	@echo "$(GREEN)Tagging and pushing telemetry image...$(RESET)"
	docker tag $(TELEMETRY_REPO_NAME):latest $(TELEMETRY_IMAGE_URI)
	@for i in 1 2 3; do \
		echo "$(YELLOW)Push attempt $$i of 3...$(RESET)"; \
		if docker push $(TELEMETRY_IMAGE_URI); then \
			echo "$(GREEN)Telemetry image pushed successfully$(RESET)"; \
			break; \
		else \
			if [ $$i -lt 3 ]; then \
				echo "$(YELLOW)Push failed, retrying in 5 seconds...$(RESET)"; \
				sleep 5; \
			else \
				echo "$(YELLOW)Push failed after 3 attempts$(RESET)"; \
				exit 1; \
			fi; \
		fi; \
	done

push-weather-service: build-weather-service
	@echo "$(GREEN)Logging into ECR...$(RESET)"
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	@echo "$(GREEN)Checking if ECR repository exists...$(RESET)"
	@aws ecr describe-repositories --repository-names $(WEATHER_REPO_NAME) --region $(AWS_REGION) 2>/dev/null || \
		(echo "$(YELLOW)Creating ECR repository $(WEATHER_REPO_NAME)...$(RESET)" && \
		aws ecr create-repository --repository-name $(WEATHER_REPO_NAME) --region $(AWS_REGION))
	@echo "$(GREEN)Tagging and pushing weather service image...$(RESET)"
	docker tag $(WEATHER_REPO_NAME):latest $(WEATHER_IMAGE_URI)
	docker push $(WEATHER_IMAGE_URI)
	@echo "$(GREEN)Weather service image pushed successfully$(RESET)"

push-heater-service: build-heater-service
	@echo "$(GREEN)Logging into ECR...$(RESET)"
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	@echo "$(GREEN)Checking if ECR repository exists...$(RESET)"
	@aws ecr describe-repositories --repository-names $(HEATER_REPO_NAME) --region $(AWS_REGION) 2>/dev/null || \
		(echo "$(YELLOW)Creating ECR repository $(HEATER_REPO_NAME)...$(RESET)" && \
		aws ecr create-repository --repository-name $(HEATER_REPO_NAME) --region $(AWS_REGION))
	@echo "$(GREEN)Tagging and pushing heater service image...$(RESET)"
	docker tag $(HEATER_REPO_NAME):latest $(HEATER_IMAGE_URI)
	@for i in 1 2 3; do \
		echo "$(YELLOW)Push attempt $$i of 3...$(RESET)"; \
		if docker push $(HEATER_IMAGE_URI); then \
			echo "$(GREEN)Heater service image pushed successfully$(RESET)"; \
			break; \
		else \
			if [ $$i -lt 3 ]; then \
				echo "$(YELLOW)Push failed, retrying in 5 seconds...$(RESET)"; \
				sleep 5; \
			else \
				echo "$(YELLOW)Push failed after 3 attempts$(RESET)"; \
				exit 1; \
			fi; \
		fi; \
	done

deploy:
	@echo "$(GREEN)Deploying CloudFormation stack...$(RESET)"
	aws cloudformation deploy \
		--template-file template.yaml \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION) \
		--parameter-overrides \
			CameraImageUri=$(CAMERA_IMAGE_URI) \
			TelemetryImageUri=$(TELEMETRY_IMAGE_URI) \
			WeatherImageUri=$(WEATHER_IMAGE_URI) \
			HeaterImageUri=$(HEATER_IMAGE_URI) \
		--capabilities CAPABILITY_NAMED_IAM \
		--tags project=house-simulator \
		--no-fail-on-empty-changeset
	@echo "$(GREEN)Deployment complete!$(RESET)"

outputs:
	@echo "$(CYAN)CloudFormation Stack Outputs:$(RESET)"
	@aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION) \
		--query 'Stacks[0].Outputs' \
		--output table

delete:
	@echo "$(YELLOW)Deleting all resources for stack $(STACK_NAME)$(RESET)"
	@echo "$(CYAN)Scaling down ECS services to stop data generation...$(RESET)"
	@CLUSTER_NAME=$$(aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION) \
		--query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' \
		--output text 2>/dev/null || echo ""); \
	if [ -n "$$CLUSTER_NAME" ]; then \
		for service in $$(aws ecs list-services --cluster $$CLUSTER_NAME --region $(AWS_REGION) --query 'serviceArns[]' --output text 2>/dev/null); do \
			echo "$(YELLOW)Scaling down service: $$(basename $$service)$(RESET)"; \
			aws ecs update-service --cluster $$CLUSTER_NAME --service $$service --desired-count 0 --region $(AWS_REGION) > /dev/null 2>&1 || true; \
		done; \
		echo "$(CYAN)Waiting 30 seconds for tasks to stop...$(RESET)"; \
		sleep 30; \
	else \
		echo "$(YELLOW)Cluster not found, skipping service scale-down$(RESET)"; \
	fi
	@echo "$(CYAN)Retrieving bucket name from stack...$(RESET)"
	@BUCKET_NAME=$$(aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION) \
		--query 'Stacks[0].Outputs[?OutputKey==`TelemetryBucketName`].OutputValue' \
		--output text 2>/dev/null || echo ""); \
	if [ -n "$$BUCKET_NAME" ]; then \
		echo "$(YELLOW)Emptying S3 bucket: $$BUCKET_NAME$(RESET)"; \
		aws s3 rm s3://$$BUCKET_NAME --recursive --region $(AWS_REGION) 2>/dev/null || true; \
	else \
		echo "$(YELLOW)Stack not found or bucket already deleted$(RESET)"; \
	fi
	@echo "$(YELLOW)Deleting ECR repositories...$(RESET)"
	@aws ecr delete-repository --repository-name $(CAMERA_REPO_NAME) --region $(AWS_REGION) --force 2>/dev/null || \
		echo "$(YELLOW)Camera repository not found or already deleted$(RESET)"
	@aws ecr delete-repository --repository-name $(TELEMETRY_REPO_NAME) --region $(AWS_REGION) --force 2>/dev/null || \
		echo "$(YELLOW)Telemetry repository not found or already deleted$(RESET)"
	@echo "$(YELLOW)Deleting CloudFormation stack...$(RESET)"
	@aws cloudformation delete-stack \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION)
	@echo "$(CYAN)Waiting for stack deletion to complete...$(RESET)"
	@aws cloudformation wait stack-delete-complete \
		--stack-name $(STACK_NAME) \
		--region $(AWS_REGION) || true
	@echo "$(GREEN)All resources deleted successfully!$(RESET)"

all: check-deps check-ecs-role push-camera-simulator push-telemetry-simulator push-weather-service push-heater-service deploy
	@echo "$(GREEN)All tasks completed successfully!$(RESET)"
