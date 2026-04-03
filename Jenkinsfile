pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    ENV_FILE = '.env.deploy'
    BACKUP_DIR = 'backups'
    PREPARE_ENV_SCRIPT = 'deployment/jenkins/scripts/prepare_env.sh'
    BACKUP_SCRIPT = 'deployment/jenkins/scripts/backup_postgres.sh'
    TEST_BACKEND_SCRIPT = 'deployment/jenkins/scripts/test_backend.sh'
    TEST_FRONTENDS_SCRIPT = 'deployment/jenkins/scripts/test_frontends.sh'
    DEPLOY_FULL_STACK_SCRIPT = 'deployment/jenkins/scripts/deploy_full_stack.sh'
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
        sh 'bash ${PREPARE_ENV_SCRIPT} "${WORKSPACE}/${ENV_FILE}"'
      }
    }

    stage('Backup Database') {
      steps {
        sh 'bash ${BACKUP_SCRIPT} "${WORKSPACE}/${ENV_FILE}" "${WORKSPACE}/${BACKUP_DIR}" "${WORKSPACE}"'
      }
    }

    stage('Backend Tests') {
      steps {
        sh 'bash ${TEST_BACKEND_SCRIPT} "${WORKSPACE}" "${WORKSPACE}/${ENV_FILE}"'
      }
    }

    stage('Frontend Tests') {
      steps {
        sh 'bash ${TEST_FRONTENDS_SCRIPT}'
      }
    }

    stage('Deploy Full Stack') {
      steps {
        sh 'bash ${DEPLOY_FULL_STACK_SCRIPT} "${WORKSPACE}/${ENV_FILE}"'
      }
    }
  }

  post {
    success {
      echo 'Full-stack Jenkins deployment pipeline succeeded.'
    }
    failure {
      echo 'Full-stack Jenkins deployment pipeline failed.'
    }
  }
}
