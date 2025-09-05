# Go Microservice

A simple Go microservice with two endpoints:

1. `GET /v1/ping` - Returns "pong"
2. `POST /v1/purchase` - Returns a dummy purchase JSON response

## Building and Running

### Prerequisites
- Docker installed on your system
- Go (optional, only needed for local development without Docker)

### Using Docker (Recommended)

1. Build the Docker image:
   ```bash
   docker build -t yourusername/go-microservice .
   ```

2. Run the container:
   ```bash
   docker run -p 8080:8080 yourusername/go-microservice
   ```

### Pushing to DockerHub

1. Log in to DockerHub:
   ```bash
   docker login
   ```

2. Tag your image:
   ```bash
   docker tag yourusername/go-microservice yourusername/go-microservice:latest
   ```

3. Push the image:
   ```bash
   docker push yourusername/go-microservice:latest
   ```

## API Endpoints

### Ping
- **URL**: `/v1/ping`
- **Method**: `GET`
- **Response**:
  ```
  pong
  ```

### Purchase
- **URL**: `/v1/purchase`
- **Method**: `POST`
- **Response**:
  ```json
  {
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "item": "Sample Product",
    "amount": 99.99,
    "status": "completed",
    "message": "Purchase processed successfully"
  }
  ```
