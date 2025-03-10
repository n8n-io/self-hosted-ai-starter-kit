docker context create ecs AIKitBuild \
  --default-vpc "vpc-5b3c4321" \
  --subnets "subnet-47ff1a49, subnet-00dd2e4d, subnet-4ea3d470, subnet-ea1937c4, subnet-10edc14c, subnet-a87556cf" \
  --security-groups "sg-008b5803844bc148d"
docker context use AIKitBuild\

sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 fs-0bba0ecccb246a550.efs.us-east-1.amazonaws.com:/ ~/efs
