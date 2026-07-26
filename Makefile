.PHONY: test run-order run-user package-order package-user package-all clean

test:
	go test ./...

run-order:
	APP_ENV=development PORT=9101 go run ./services/order

run-user:
	APP_ENV=development PORT=9102 go run ./services/user

package-order:
	./scripts/build-custom-runtime.sh order

package-user:
	./scripts/build-custom-runtime.sh user

package-all: package-order package-user

clean:
	rm -rf ./dist

