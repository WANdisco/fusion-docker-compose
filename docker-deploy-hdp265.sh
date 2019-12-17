#!/usr/bin/env sh
#This script downloads HDP sandbox along with their proxy docker container
set -x

# CAN EDIT THESE VALUES
registry="hortonworks"
name="sandbox-hdp"
version="2.6.5"
proxyName="sandbox-proxy"
proxyVersion="1.0"
flavor="hdp"

# NO EDITS BEYOND THIS LINE
# housekeeping
echo $flavor > sandbox-flavor


# create necessary folders for nginx and copy over our rule generation script there
mkdir -p sandbox/proxy/conf.d
mkdir -p sandbox/proxy/conf.stream.d

# pull and tag the sandbox and the proxy container
docker pull "$registry/$name:$version"
#docker pull "$registry/$proxyName:$proxyVersion"
docker build --build-arg "repository=$registry/$name" --build-arg "tag=$version" -f "Dockerfile.$name" -t "local/$name:$version" .


# start the docker container and proxy
if [ "$flavor" = "hdf" ]; then
 hostname="sandbox-hdf.hortonworks.com"
elif [ "$flavor" = "hdp" ]; then
 hostname="sandbox-hdp.hortonworks.com"
fi

echo Setting hostname to: $hostname
version=$(docker images | grep hortonworks/$name  | awk '{print $2}');

# Create cda docker network
docker network create fusion_fusion 2>/dev/null

# Deploy the sandbox into the cda docker network
docker run \
  --name $name \
  -d \
  -p 8080:8080 -p 88:88 -p 88:88/udp -p 749:749 \
  --privileged \
  -h $hostname \
  --network=fusion_fusion \
  --network-alias=$hostname \
  "local/$name:$version"

echo " Remove existing postgres run files. Please wait"
sleep 2
docker exec -t "$name" sh -c "rm -rf /var/run/postgresql/*; systemctl restart postgresql"


#Deploy the proxy container.
#sed 's/sandbox-hdp-security/sandbox-hdp/g' assets/generate-proxy-deploy-script.sh > assets/generate-proxy-deploy-script.sh.new
#mv -f assets/generate-proxy-deploy-script.sh.new assets/generate-proxy-deploy-script.sh
#chmod +x assets/generate-proxy-deploy-script.sh
#assets/generate-proxy-deploy-script.sh 2>/dev/null

#check to see if it's windows
#if uname | grep MINGW; then 
# sed -i -e 's/\( \/[a-z]\)/\U\1:/g' sandbox/proxy/proxy-deploy.sh
#fi
#chmod +x sandbox/proxy/proxy-deploy.sh 2>/dev/null
# sandbox/proxy/proxy-deploy.sh 
