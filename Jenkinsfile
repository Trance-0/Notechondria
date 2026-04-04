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
    DEPLOY_BACKEND_SCRIPT = 'deployment/jenkins/scripts/deploy_backend.sh'
    DEPLOY_FRONTENDS_SCRIPT = 'deployment/jenkins/scripts/deploy_frontends.sh'
    DEPLOY_GATEWAY_SCRIPT = 'deployment/jenkins/scripts/deploy_gateway.sh'
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
            sh 'bash ${TEST_BACKEND_SCRIPT} "${WORKSPACE}" "${WORKSPACE}/${ENV_FILE}"'
          }
        }
        stage('Frontend Tests') {
          steps {
            sh 'bash ${TEST_FRONTENDS_SCRIPT}'
          }
        }
      }
    }

    stage('Deploy') {
      parallel {
        stage('Backend Deploy') {
          steps {
            sh 'bash ${DEPLOY_BACKEND_SCRIPT} "${WORKSPACE}" "${WORKSPACE}/${ENV_FILE}" "${WORKSPACE}/deployment/jenkins/scripts/wait_for_stack.sh" "300" "${WORKSPACE}/deployment/jenkins/scripts/ensure_db_ready.sh"'
          }
        }
        stage('Frontend Deploy') {
          steps {
            sh 'bash ${DEPLOY_FRONTENDS_SCRIPT} "${WORKSPACE}/${ENV_FILE}"'
          }
        }
      }
    }

    stage('Gateway Finalize') {
      steps {
        sh 'bash ${DEPLOY_GATEWAY_SCRIPT} "${WORKSPACE}/${ENV_FILE}"'
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
