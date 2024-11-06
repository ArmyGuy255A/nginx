# This script exports the docker image to a tar file
function ConvertTo-DockerFileName ($imageName) {
    return $imageName.Replace("/", "--").Replace(":","_")
}
$imageName = "armyguy255a/nginx:alpine-1.26.2"
$saveName = ("{0}.tar.gz" -f (ConvertTo-DockerFileName -imageName $imageName)) 
docker save -o $saveName $imageName