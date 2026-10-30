pipeline {
  agent { label 'local-docker' }
  options {
    timestamps()
    disableConcurrentBuilds()
    skipDefaultCheckout(true)
    timeout(time: 120, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }
  parameters {
    string(name: 'DEPLOY_ENV_SOURCE', defaultValue: '/var/lib/jenkins/secrets/notechondria-deploy.env', description: 'Private env file on the build agent.')
  }
  environment {
    ENV_FILE = '.env.deploy'
    DEPLOY_ENV_SOURCE = "${params.DEPLOY_ENV_SOURCE}"
    ENV_FILE_PATH = "${WORKSPACE}/.env.deploy"
    COMPOSE_PARALLEL_LIMIT = '1'
    BUILDX_BUILDER = 'notechondria-local'
    BACKUP_DIR = '/var/lib/jenkins/backups/notechondria'
    NO_PROXY = 'localhost,127.0.0.1,::1'
    no_proxy = 'localhost,127.0.0.1,::1'
  }
  triggers { githubPush() }
  stages {
    stage('Checkout GitHub main') {
      steps {
        deleteDir()
        script {
          def revision = checkout scm
          env.GIT_COMMIT = revision.GIT_COMMIT
        }
      }
    }
    stage('Prepare environment') {
      steps {
        sh 'bash deployment/jenkins/scripts/prepare_env.sh "$WORKSPACE/$ENV_FILE" "$DEPLOY_ENV_SOURCE"'
      }
    }
    stage('Build resources') {
      steps { sh 'bash deployment/jenkins/scripts/prepare_builder.sh' }
    }
    stage('Backend tests') {
      steps { sh 'bash deployment/jenkins/scripts/test_backend.sh "$WORKSPACE" "$WORKSPACE/$ENV_FILE"' }
    }
    stage('Frontend tests') {
      steps { sh 'bash deployment/jenkins/scripts/test_frontends.sh' }
    }
    stage('Database backup') {
      steps { sh 'timeout 5m bash deployment/jenkins/scripts/backup_postgres.sh "$WORKSPACE/$ENV_FILE" "$BACKUP_DIR" "$WORKSPACE"' }
    }
    stage('Backend deployment') {
      steps { sh 'bash deployment/jenkins/scripts/deploy_backend.sh "$WORKSPACE" "$WORKSPACE/$ENV_FILE"' }
    }
    stage('Frontend deployment') {
      steps { sh 'bash deployment/jenkins/scripts/deploy_frontends.sh "$WORKSPACE/$ENV_FILE"' }
    }
    stage('Gateway and health verification') {
      steps {
        sh 'bash deployment/jenkins/scripts/deploy_gateway.sh "$WORKSPACE/$ENV_FILE"'
        sh 'bash deployment/jenkins/scripts/verify_deployment.sh "$WORKSPACE/$ENV_FILE"'
      }
    }
  }
  post {
    always { sh 'rm -f "$WORKSPACE/$ENV_FILE"' }
    success { echo 'Deployment verified: Jenkins.Deploy/complete — backend and all three frontend routes passed HTTP checks.' }
    failure { echo 'Deployment incomplete: Jenkins.Deploy/pipeline — a required stage failed; inspect the failed stage console.' }
  }
}
