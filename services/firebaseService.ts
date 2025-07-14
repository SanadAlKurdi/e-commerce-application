import { db } from '../firebase/config';
import {
  collection,
  getDocs,
  addDoc,
  updateDoc,
  deleteDoc,
  doc,
  query,
  orderBy,
  limit,
  startAfter,
  where,
} from 'firebase/firestore';

export interface Product {
  id?: string;
  title: string;
  description: string;
  price: number;
  imageUrl: string;
  stock: number;
  category: string;
}

const COLLECTION = 'products';
const PAGE_SIZE = 10;

export const fetchProducts = async (
  lastVisible: any = null,
  search: string = ''
): Promise<{ data: Product[]; lastDoc: any }> => {
  let q = query(collection(db, COLLECTION), orderBy('title'), limit(PAGE_SIZE));

  if (lastVisible) {
    q = query(q, startAfter(lastVisible));
  }

  if (search.trim()) {
    q = query(
      collection(db, COLLECTION),
      where('title', '>=', search),
      where('title', '<=', search + '\uf8ff'),
      orderBy('title'),
      limit(PAGE_SIZE)
    );
  }

  const snapshot = await getDocs(q);
  const data = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })) as Product[];

  return {
    data,
    lastDoc: snapshot.docs[snapshot.docs.length - 1],
  };
};

export const addProduct = async (product: Product) => {
  await addDoc(collection(db, COLLECTION), product);
};

export const updateProduct = async (id: string, product: Partial<Product>) => {
  const ref = doc(db, COLLECTION, id);
  await updateDoc(ref, product);
};

export const deleteProduct = async (id: string) => {
  const ref = doc(db, COLLECTION, id);
  await deleteDoc(ref);
};
