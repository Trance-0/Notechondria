pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    ENV_FILE = '.env.deploy'
    BACKUP_DIR = 'backups'
    DEPLOY_SCRIPT = 'deployment/scripts/deploy_backend.sh'
    FRONTEND_DEPLOY_SCRIPT = 'deployment/scripts/deploy_frontend.sh'
    BACKUP_SCRIPT = 'deployment/scripts/backup_postgres.sh'
    TEST_SCRIPT = 'deployment/scripts/test_backend.sh'
    FRONTEND_TEST_SCRIPT = 'deployment/scripts/test_frontend.sh'
    PREPARE_ENV_SCRIPT = 'deployment/scripts/prepare_env.sh'
    WAIT_SCRIPT = 'deployment/scripts/wait_for_stack.sh'
    FRONTEND_WAIT_SCRIPT = 'deployment/scripts/wait_for_frontend.sh'
    DB_READY_SCRIPT = 'deployment/scripts/ensure_db_ready.sh'
    WAIT_TIMEOUT_SECONDS = '300'
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

    stage('Test') {
      parallel {
        stage('Backend Tests') {
          steps {
            sh 'bash ${TEST_SCRIPT} "${WORKSPACE}" "${WORKSPACE}/${ENV_FILE}"'
          }
        }
        stage('Frontend Tests') {
          steps {
            sh 'bash ${FRONTEND_TEST_SCRIPT} "${WORKSPACE}" "${WORKSPACE}/${ENV_FILE}"'
          }
        }
      }
    }

    stage('Build and Deploy') {
      parallel {
        stage('Deploy Backend') {
          steps {
            sh 'bash ${DEPLOY_SCRIPT} "${WORKSPACE}" "${WORKSPACE}/${ENV_FILE}" "${WORKSPACE}/${WAIT_SCRIPT}" "${WAIT_TIMEOUT_SECONDS}" "${WORKSPACE}/${DB_READY_SCRIPT}"'
          }
        }
        stage('Deploy Frontend') {
          steps {
            sh 'bash ${FRONTEND_DEPLOY_SCRIPT} "${WORKSPACE}" "${WORKSPACE}/${ENV_FILE}" "${WORKSPACE}/${FRONTEND_WAIT_SCRIPT}" "${WAIT_TIMEOUT_SECONDS}"'
          }
        }
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
