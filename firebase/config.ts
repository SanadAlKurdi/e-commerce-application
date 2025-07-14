import { initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';

const firebaseConfig = {
  apiKey: "AIzaSyA6S-EXAMPLE-KEY-REPLACE_THIS",
  authDomain: "ecommerceapp-9204a.firebaseapp.com",
  projectId: "ecommerceapp-9204a",
  storageBucket: "ecommerceapp-9204a.appspot.com",
  messagingSenderId: "924679821234",
  appId: "1:924679821234:web:abcdef123456"
};

const app = initializeApp(firebaseConfig);

export const auth = getAuth(app);
export const db = getFirestore(app);
