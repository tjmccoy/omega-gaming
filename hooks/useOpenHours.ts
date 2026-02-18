"use client";

import { useEffect, useState } from "react";

// 1. Define the logic outside the hook so it's clean
const checkIsOpen = (date: Date) => {
  const hour = date.getHours();
  // Adjust these hours to match your lottery's schedule
  return hour >= 8 && hour < 20; // Open 8 AM to 8 PM
};

export const useOpenHours = () => {
  const [isInitialized, setIsInitialized] = useState(false);

  // 2. Initialize state with the actual time immediately.
  // This prevents the "false" default that causes the red flash.
  const [currentTime, setCurrentTime] = useState(new Date());
  const [isOpen, setIsOpen] = useState<boolean | undefined>(undefined); // Start as undefined to indicate "not ready"
  const [isClosingSoon, setIsClosingSoon] = useState(false);
  const [timeRemaining, setTimeRemaining] = useState("");

  useEffect(() => {
    const updateStatus = () => {
      const now = new Date();
      const currentIsOpen = checkIsOpen(now);

      setCurrentTime(now);
      setIsOpen(currentIsOpen);

      // Example Closing Soon logic: 30 minutes before 8 PM
      const closingTime = new Date(now);
      closingTime.setHours(20, 0, 0);
      const diff = closingTime.getTime() - now.getTime();

      const thirtyMinutes = 30 * 60 * 1000;
      setIsClosingSoon(currentIsOpen && diff > 0 && diff < thirtyMinutes);

      // Format time remaining (HH:MM:SS)
      if (diff > 0) {
        const hours = Math.floor(diff / (1000 * 60 * 60));
        const mins = Math.floor((diff / (1000 * 60)) % 60);
        const secs = Math.floor((diff / 1000) % 60);
        setTimeRemaining(`${hours}:${mins.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`);
      }
      setIsInitialized(true); // Mark as initialized after the first check
    };

    updateStatus(); // Call immediately to set initial state
    const timer = setInterval(updateStatus, 1000);

    return () => clearInterval(timer);
  }, []);

  return {
    currentTime,
    isOpen,
    isClosingSoon,
    timeRemaining,
    isInitialized, // Tell the UI we are ready to show the real data
  };
};
