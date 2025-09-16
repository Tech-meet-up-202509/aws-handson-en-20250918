init:
	terraform init

plan:
	terraform plan -out tf.plan

apply:
	terraform apply -auto-approve

destroy:
	terraform destroy -auto-approve

quick:
	terraform init && terraform apply -auto-approve

env:
	echo Using name_prefix=$${TF_VAR_name_prefix:-eks-hands-on}
