pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    PROJECT_DIR = '/var/lib/jenkins/workspace/Notechondria'
    ENV_FILE = '.env.deploy'
    BACKUP_DIR = '/var/backups/notechondria'
    DEPLOY_SCRIPT = 'deployment/scripts/deploy_backend.sh'
    BACKUP_SCRIPT = 'deployment/scripts/backup_postgres.sh'
    PREPARE_ENV_SCRIPT = 'deployment/scripts/prepare_env.sh'
    JENKINS_ENV_CREDENTIAL_ID = 'notechondria-deploy-env'
  }

  triggers {
    githubPush()
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Prepare Environment') {
      steps {
        withCredentials([file(credentialsId: "${JENKINS_ENV_CREDENTIAL_ID}", variable: 'JENKINS_ENV_FILE')]) {
          sh 'bash ${PREPARE_ENV_SCRIPT} ${PROJECT_DIR}/${ENV_FILE} ${JENKINS_ENV_FILE}'
        }
      }
    }

    stage('Backup Database') {
      steps {
        sh 'bash ${BACKUP_SCRIPT} ${PROJECT_DIR}/${ENV_FILE} ${BACKUP_DIR}'
      }
    }

    stage('Test') {
      steps {
        sh 'python backend/manage.py test --settings=notechondria.settings_test'
      }
    }

    stage('Build and Deploy') {
      steps {
        sh 'bash ${DEPLOY_SCRIPT} ${PROJECT_DIR} ${PROJECT_DIR}/${ENV_FILE}'
      }
    }
  }

  post {
    success {
      echo 'Deployment pipeline succeeded.'
    }
    failure {
      echo 'Deployment pipeline failed. Check backup and test stages before retrying.'
    }
  }
}
