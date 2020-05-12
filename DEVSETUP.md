### SorterBot Setup for Development
1. Make sure you have [Docker](https://docs.docker.com/get-docker/), [Docker Compose](https://docs.docker.com/compose/install/), [AWS CLI Version 2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) and [Git LFS](https://git-lfs.github.com/) installed.
1. Clone the SorterBot Cloud repository:
    ```
    git clone https://github.com/simonszalai/sorterbot_cloud.git
    ```
1. `cd sorterbot_cloud`, then build the image in Development Mode:
    ```
    docker build -t sorterbot_cloud --build-arg DEVMODE=1 .
    ```
1. `cd ..`, then clone the SorterBot Control Panel repository:
    ```
    git clone https://github.com/simonszalai/sorterbot_control.git
    ```
1. `cd sorterbot_control`, then build the Docker image:
    ```
    docker build -t sorterbot_control .
    ```
1. For full functionality, you need AWS credentials that provide at least Full S3 access for both SorterBot Cloud and Control Panel. If you want to experiment with additional AWS services and you are less concerned about the safety of your account, you might consider adding root credentials. You can also completely disable AWS (by providing DISABLE_AWS environment variable for both services), but in that case, the stitched images will not show up in the control panel. (You can still view them as local files). If you want to make credentials available in your system, you can do that by executing `aws configure`.
