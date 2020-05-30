# SorterBot Installer

This is the root repository for the SorterBot project, where you can find instructions to set up a development environment, as well as directions to deploy the solution to AWS. The project consists of the following repositories:

- **SorterBot Installer**: Current repository, automates setup for development and deployment to AWS.
- **[SorterBot Cloud](https://github.com/simonszalai/sorterbot_cloud)**: Handles compute heavy tasks, it can be deployed to an AWS ECS cluster.
- **[SorterBot Control](https://github.com/simonszalai/sorterbot_control)**: A Django app, which serves as a central control panel, it communicates with the Raspberry Pis, SorterBot Cloud, and the PostgreSQL database.
- **[SorterBot Raspberry](https://github.com/simonszalai/sorterbot_raspberry)**: Python script to be executed on the Raspberry Pis to record data and execute commands.
- **[SorterBot LabelTool](https://github.com/simonszalai/sorterbot_labeltool)**: Labeling tools written in Python to speed up training dataset creation.

## Development
There are two options to set up a development environment: *local* and *aws-dev*. 

### Local
In *local* mode, the solution can be run without any AWS resources. Even without Internet, as long as the Raspberry Pis are connected to the same local network. To set up the development environment, follow the steps below:

1. Install [Git LFS](https://git-lfs.github.com/) in case you don't have it installed.
1. Clone the SorterBot Installer, Cloud and Control repositories:
    ```
    git clone git@github.com:simonszalai/sorterbot_installer.git
    git clone git@github.com:simonszalai/sorterbot_cloud.git
    git clone git@github.com:simonszalai/sorterbot_control.git
    ```
1. You will need a PostgreSQL database. You can connect to any database, either one deployed to a cloud provider or on localhost. To start a PostgreSQL instance as a Docker image on your local computer, follow these steps:
    1. Download and run a PostgreSQL image from Docker Hub. In the command below, change [ANY_NAME] to a name of your choice, and [SECRET_PASSWORD] to a password, that later you will use as part of the connection string.
        ```
        docker run --name [ANY_NAME] -e POSTGRES_PASSWORD=[SECRET_PASSWORD] -d postgres:11
        ```
   1. After your postgres instance started, run `docker ps`, and copy the CONTAINER ID of the Docker container that runs your database.
   1. Run `docker inspect [CONTAINER ID]`, and in the output, find `NetworkSettings.Networks.bridge.IPAddress`. This will be the host in your connection string. The password will be what you specified above, the port is the default, `5432`, and the username and dbname are both `postgres`. Based on these information, you will be able to construct the connection string in the next step.
1. Follow the instructions under *Run SorterBot Control locally* in the [SorterBot Control](https://github.com/simonszalai/sorterbot_control) repository's README. Run the Docker image in *local* mode.
1. Follow the instructions under *Run SorterBot Cloud locally* in the [SorterBot Cloud](https://github.com/simonszalai/sorterbot_cloud) repository's README. Run the Docker image in *local* mode.