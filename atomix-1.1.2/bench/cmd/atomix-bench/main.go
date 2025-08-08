// SPDX-FileCopyrightText: 2022-present Intel Corporation
//
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"context"
	"fmt"
	"github.com/atomix/atomix/api/errors"
	"github.com/atomix/atomix/runtime/pkg/logging"
	"github.com/atomix/atomix/runtime/pkg/utils/async"
	"github.com/atomix/go-sdk/pkg/atomix"
	"github.com/atomix/go-sdk/pkg/types"
	"github.com/google/uuid"
	"github.com/spf13/cobra"
	"math/rand"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"
)

var log = logging.GetLogger()

func init() {
	logging.SetLevel(logging.InfoLevel)
}

func main() {
	cmd := getCommand()
	if err := cmd.Execute(); err != nil {
		panic(err)
	}
}

func getCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use: "atomix-bench",
	}
	cmd.AddCommand(getCounterCommand())
	cmd.AddCommand(getMapCommand())
	cmd.AddCommand(getSetCommand())

	cmd.PersistentFlags().StringP("name", "n", "test", "the name of the primitive to use")
	cmd.PersistentFlags().IntP("concurrency", "c", 100, "the number of concurrent operations to run")
	cmd.PersistentFlags().Float32P("write-percentage", "w", .5, "the percentage of operations to perform as writes")
	cmd.PersistentFlags().DurationP("sample-interval", "i", 10*time.Second, "the interval at which to sample performance")
	return cmd
}

func getCounterCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use: "counter",
		Run: func(cmd *cobra.Command, args []string) {
			c, err := atomix.Counter("test").
				Get(context.Background())
			if err != nil {
				fmt.Fprintln(cmd.OutOrStderr(), err.Error())
				os.Exit(1)
			}

			runBenchmark(cmd,
				func(n int) {
					if n%2 == 0 {
						if _, err := c.Increment(context.Background(), rand.Int63n(10)); err != nil {
							log.Warn(err)
						}
					} else {
						if _, err := c.Decrement(context.Background(), rand.Int63n(10)); err != nil {
							log.Warn(err)
						}
					}
				}, func(int) {
					if _, err := c.Get(context.Background()); err != nil {
						log.Warn(err)
					}
				})
		},
	}
	cmd.Flags().IntP("num-keys", "k", 1000, "the number of unique map keys to use")
	return cmd
}

func getMapCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use: "map",
		Run: func(cmd *cobra.Command, args []string) {
			numKeys, err := cmd.Flags().GetInt("num-keys")
			if err != nil {
				fmt.Fprintln(cmd.OutOrStderr(), err.Error())
				os.Exit(1)
			}

			m, err := atomix.Map[string, string]("test").
				Codec(types.Scalar[string]()).
				Get(context.Background())
			if err != nil {
				fmt.Fprintln(cmd.OutOrStderr(), err.Error())
				os.Exit(1)
			}

			keys := make([]string, numKeys)
			for i := 0; i < numKeys; i++ {
				keys[i] = uuid.New().String()
			}

			err = async.IterAsync(numKeys, func(i int) error {
				_, err := m.Put(context.Background(), keys[i], uuid.New().String())
				return err
			})
			if err != nil {
				fmt.Fprintln(cmd.OutOrStderr(), err.Error())
				os.Exit(1)
			}

			runBenchmark(cmd,
				func(n int) {
					if n%2 == 0 {
						if _, err := m.Put(context.Background(), keys[rand.Intn(numKeys)], keys[rand.Intn(numKeys)]); err != nil {
							log.Warn(err)
						}
					} else {
						if _, err := m.Remove(context.Background(), keys[rand.Intn(numKeys)]); err != nil {
							if !errors.IsNotFound(err) {
								log.Warn(err)
							}
						}
					}
				}, func(int) {
					if _, err := m.Get(context.Background(), keys[rand.Intn(numKeys)]); err != nil {
						if !errors.IsNotFound(err) {
							log.Warn(err)
						}
					}
				})
		},
	}
	cmd.Flags().IntP("num-keys", "k", 1000, "the number of unique map keys to use")
	return cmd
}

func getSetCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use: "set",
		Run: func(cmd *cobra.Command, args []string) {
			numElements, err := cmd.Flags().GetInt("num-elements")
			if err != nil {
				fmt.Fprintln(cmd.OutOrStderr(), err.Error())
				os.Exit(1)
			}

			m, err := atomix.Set[string]("test").
				Codec(types.Scalar[string]()).
				Get(context.Background())
			if err != nil {
				fmt.Fprintln(cmd.OutOrStderr(), err.Error())
				os.Exit(1)
			}

			elements := make([]string, numElements)
			for i := 0; i < numElements; i++ {
				elements[i] = uuid.New().String()
			}

			err = async.IterAsync(numElements, func(i int) error {
				_, err := m.Add(context.Background(), elements[i])
				return err
			})
			if err != nil {
				fmt.Fprintln(cmd.OutOrStderr(), err.Error())
				os.Exit(1)
			}

			runBenchmark(cmd,
				func(n int) {
					if n%2 == 0 {
						if _, err := m.Add(context.Background(), elements[rand.Intn(numElements)]); err != nil {
							log.Warn(err)
						}
					} else {
						if _, err := m.Remove(context.Background(), elements[rand.Intn(numElements)]); err != nil {
							log.Warn(err)
						}
					}
				}, func(int) {
					if _, err := m.Contains(context.Background(), elements[rand.Intn(numElements)]); err != nil {
						log.Warn(err)
					}
				})
		},
	}
	cmd.Flags().IntP("num-elements", "e", 1000, "the number of unique set elements to use")
	return cmd
}

func runBenchmark(cmd *cobra.Command, writer func(int), reader func(int)) {
	concurrency, err := cmd.Flags().GetInt("concurrency")
	if err != nil {
		fmt.Fprintln(cmd.OutOrStderr(), err.Error())
		os.Exit(1)
	}
	sampleInterval, err := cmd.Flags().GetDuration("sample-interval")
	if err != nil {
		fmt.Fprintln(cmd.OutOrStderr(), err.Error())
		os.Exit(1)
	}
	writePercentage, err := cmd.Flags().GetFloat32("write-percentage")
	if err != nil {
		fmt.Fprintln(cmd.OutOrStderr(), err.Error())
		os.Exit(1)
	}

	if writePercentage > 1 {
		panic("writePercentage must be a decimal value between 0 and 1")
	}

	log.Infof("Starting benchmark...")
	log.Infof("concurrency: %d", concurrency)
	log.Infof("sampleInterval: %s", sampleInterval)
	log.Infof("writePercentage: %f", writePercentage)

	opCount := &atomic.Uint64{}
	totalDuration := &atomic.Int64{}
	for i := 0; i < concurrency; i++ {
		go func() {
			for {
				start := time.Now()
				n := rand.Intn(100)
				if n < int(writePercentage*100) {
					writer(n)
				} else {
					reader(n)
				}
				totalDuration.Add(int64(time.Since(start)))
				opCount.Add(1)
			}
		}()
	}

	// Wait for an interrupt signal
	signalCh := make(chan os.Signal, 2)
	signal.Notify(signalCh, os.Interrupt, syscall.SIGTERM)

	ticker := time.NewTicker(10 * time.Second)
	for {
		select {
		case <-ticker.C:
			count := opCount.Swap(0)
			duration := totalDuration.Swap(0)
			if count > 0 {
				log.Infof("Completed %d operations in %s (~%s/request)", count, sampleInterval, time.Duration(duration/int64(count)))
			}
		case <-signalCh:
			return
		}
	}
}
